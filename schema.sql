-- POS System Database Schema

-- 1. Enable Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Create Enums
CREATE TYPE user_role AS ENUM ('ADMIN', 'MANAGER', 'CASHIER');
CREATE TYPE payment_method AS ENUM ('CASH', 'MOBILE_MONEY', 'CARD');
CREATE TYPE order_status AS ENUM ('COMPLETED', 'VOIDED', 'REFUNDED');
CREATE TYPE notification_type AS ENUM ('LOW_STOCK', 'OUT_OF_STOCK', 'SYSTEM');

-- 3. Profiles Table
CREATE TABLE profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  role user_role NOT NULL DEFAULT 'CASHIER',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Products Table
CREATE TABLE products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  description TEXT,
  sku TEXT UNIQUE,
  barcode TEXT UNIQUE,
  category TEXT NOT NULL,
  price DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  cost_price DECIMAL(12,2) DEFAULT 0.00,
  quantity INTEGER NOT NULL DEFAULT 0,
  low_stock_threshold INTEGER NOT NULL DEFAULT 5,
  image_url TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Customers Table
CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  full_name TEXT NOT NULL,
  email TEXT UNIQUE,
  phone TEXT,
  address TEXT,
  loyalty_points INTEGER DEFAULT 0,
  tier TEXT DEFAULT 'BRONZE' CHECK (tier IN ('BRONZE', 'SILVER', 'GOLD')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Sales Table
CREATE TABLE sales (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  user_id UUID REFERENCES profiles(id) NOT NULL,
  subtotal DECIMAL(12,2) NOT NULL,
  discount_amount DECIMAL(12,2) DEFAULT 0.00,
  discount_type TEXT DEFAULT 'FIXED' CHECK (discount_type IN ('FIXED', 'PERCENTAGE')),
  tax_amount DECIMAL(12,2) NOT NULL,
  total_amount DECIMAL(12,2) NOT NULL,
  status order_status DEFAULT 'COMPLETED',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Sale Items Table
CREATE TABLE sale_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sale_id UUID REFERENCES sales(id) ON DELETE CASCADE NOT NULL,
  product_id UUID REFERENCES products(id) NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  subtotal DECIMAL(12,2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Payments Table
CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sale_id UUID REFERENCES sales(id) ON DELETE CASCADE NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  method payment_method NOT NULL,
  provider_reference TEXT,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Suppliers Table
CREATE TABLE suppliers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  contact_person TEXT,
  email TEXT,
  phone TEXT,
  address TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Purchase Orders Table
CREATE TABLE purchase_orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  supplier_id UUID REFERENCES suppliers(id) ON DELETE CASCADE NOT NULL,
  total_amount DECIMAL(12,2) NOT NULL,
  status TEXT DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'RECEIVED', 'CANCELLED')),
  received_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. Audit Logs Table
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES profiles(id),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  old_data JSONB,
  new_data JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. Notifications Table
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  type notification_type DEFAULT 'SYSTEM',
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13. Settings Table
CREATE TABLE settings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  store_name TEXT NOT NULL DEFAULT 'My POS Store',
  store_address TEXT,
  store_phone TEXT,
  store_email TEXT,
  store_logo_url TEXT,
  currency_code TEXT DEFAULT 'GHS',
  tax_rate DECIMAL(5,2) DEFAULT 15.00,
  receipt_footer TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13.5. Product Variants Table
CREATE TABLE product_variants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id UUID REFERENCES products(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  sku TEXT,
  price DECIMAL(12,2) NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 14. Functions & Triggers

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_customers_updated_at BEFORE UPDATE ON customers FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_suppliers_updated_at BEFORE UPDATE ON suppliers FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_purchase_orders_updated_at BEFORE UPDATE ON purchase_orders FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON product_variants FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_settings_updated_at BEFORE UPDATE ON settings FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- Function to handle new user profile creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  resolved_role public.user_role;
BEGIN
  resolved_role := CASE UPPER(COALESCE(NEW.raw_user_meta_data->>'role', ''))
    WHEN 'ADMIN' THEN 'ADMIN'::public.user_role
    WHEN 'MANAGER' THEN 'MANAGER'::public.user_role
    WHEN 'CASHIER' THEN 'CASHIER'::public.user_role
    ELSE 'CASHIER'::public.user_role
  END;

  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (NEW.id, NEW.email, NEW.raw_user_meta_data->>'full_name', resolved_role)
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role,
    updated_at = NOW();

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Do not block auth user creation if profile sync fails.
    RAISE WARNING 'handle_new_user failed for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 15. Row Level Security (RLS) Policies

-- Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;

-- 14.5 Helper Function for RLS (to avoid recursion)
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT role = 'ADMIN' FROM profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

-- Profiles Policies
CREATE POLICY "Profiles are viewable by everyone" ON profiles FOR SELECT USING (true);
CREATE POLICY "Allow inserts for new users" ON profiles FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Admins can update all profiles" ON profiles FOR UPDATE USING (is_admin());
CREATE POLICY "Admins can delete all profiles" ON profiles FOR DELETE USING (is_admin());

-- Products Policies
CREATE POLICY "Products are viewable by everyone" ON products FOR SELECT USING (true);
CREATE POLICY "Managers and Admins can manage products" ON products FOR ALL USING (
  is_admin() OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'MANAGER')
);

-- Customers Policies
CREATE POLICY "All authenticated users can manage customers" ON customers FOR ALL USING (auth.uid() IS NOT NULL);

-- Sales & Payments Policies
CREATE POLICY "All authenticated users can view sales" ON sales FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "All authenticated users can insert sales" ON sales FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Managers and Admins can manage sales" ON sales FOR ALL USING (
  is_admin() OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'MANAGER')
);

CREATE POLICY "All authenticated users can view payments" ON payments FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "All authenticated users can insert payments" ON payments FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Sale Items Policies
CREATE POLICY "All authenticated users can view sale items" ON sale_items FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "All authenticated users can insert sale items" ON sale_items FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Audit Logs Policies
CREATE POLICY "Admins can view audit logs" ON audit_logs FOR SELECT USING (is_admin());
CREATE POLICY "All users can insert audit logs" ON audit_logs FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Notifications Policies
CREATE POLICY "All users can view notifications" ON notifications FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "All users can update their own notifications" ON notifications FOR UPDATE USING (auth.uid() IS NOT NULL);

-- Settings Policies
CREATE POLICY "Settings are viewable by all users" ON settings FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "Admins can manage settings" ON settings FOR ALL USING (is_admin());

-- Suppliers Policies
CREATE POLICY "All authenticated users can view suppliers" ON suppliers FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "Managers and Admins can manage suppliers" ON suppliers FOR ALL USING (
  is_admin() OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'MANAGER')
);

-- Purchase Orders Policies
CREATE POLICY "All authenticated users can view purchase orders" ON purchase_orders FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "Managers and Admins can manage purchase orders" ON purchase_orders FOR ALL USING (
  is_admin() OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'MANAGER')
);

-- Product Variants Policies
CREATE POLICY "All users can view product variants" ON product_variants FOR SELECT USING (true);
CREATE POLICY "Managers and Admins can manage product variants" ON product_variants FOR ALL USING (
  is_admin() OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'MANAGER')
);

-- 16. Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE products;

-- 17. Initial Data
INSERT INTO settings (store_name, tax_rate) VALUES ('Point of Sale', 15.00);
