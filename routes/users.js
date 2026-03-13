const express = require('express');
const router = express.Router();
const { supabaseAdmin } = require('../config/supabase');
const { z } = require('zod');

const userSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
  full_name: z.string().min(2),
  role: z.enum(['ADMIN', 'MANAGER', 'CASHIER']),
});

// Create new user (Admin only operation)
router.post('/create', async (req, res) => {
  try {
    const validatedData = userSchema.parse(req.body);

    const { data: userData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email: validatedData.email,
      password: validatedData.password,
      email_confirm: true,
      user_metadata: {
        full_name: validatedData.full_name,
        role: validatedData.role,
      },
    });

    if (authError) {
      return res.status(400).json({ error: authError.message });
    }

    res.json({ user: userData.user });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return res.status(400).json({ error: error.errors });
    }
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
