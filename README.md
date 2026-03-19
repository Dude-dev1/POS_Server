# Cortex POS: Standalone Backend 🚀

This is a decoupled Node.js/Express backend specifically designed for use with a standalone frontend (like React/Vite).

## Getting Started

1.  **Clone the Repository**:

    ```bash
    git clone <your-new-repo-url>
    cd pos-backend
    ```

2.  **Install Dependencies**:

    ```bash
    npm install
    ```

3.  **Environment Setup**:

    - Copy `.env.example` to `.env`:
      ```bash
      cp .env.example .env
      ```
    - Fill in your **Supabase Project URL** and **Service Role Key** (required for admin operations).

4.  **Database Setup**:

    - Go to your Supabase Dashboard -> SQL Editor.
    - Copy the contents of `schema.sql` and run them to initialize your tables, enums, triggers, and RLS policies.

5.  **Run the Server**:
    ```bash
    npm run dev
    ```
    The server will be running at `http://localhost:5000`.

## API Endpoints

### User Management

- **POST `/api/users/create`**: Creates a new user with a specific role. Use this from your Vite frontend to add staff members.
  - Body: `{ "email": "...", "password": "...", "full_name": "...", "role": "CASHIER|MANAGER|ADMIN" }`

## Integration with React/Vite

Since this is a decoupled backend, your Vite frontend should use the **Supabase JS SDK** for most operations (fetching products, processing sales) and use the **Backend API** (this project) for administrative tasks like creating new users.

---
