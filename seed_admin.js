db = db.getSiblingDB('surveillance');

// Ensure unique index on identity_number to prevent duplicates
db.users.createIndex({ identity_number: 1 }, { unique: true });

// Only insert if admin doesn't already exist
const existing = db.users.findOne({ identity_number: 'admin' });

// User Creds = admin : admin
if (existing) {
  print('Admin already exists — skipping insert.');
} else {
  db.users.insertOne({
    name:            'Admin',
    surname:         'System',
    identity_number: 'admin',
    phone_number:    '00000000',
    role:            'admin',
    password_hash:   '$2b$12$7WvUnGpbGWpM01UNUqE3ROtVfy.sOuGcdewEzG7XTpz9c2gpIHB62',
    created_by:      'system',
    created_at:      new Date(),
    is_active:       true
  });
  print('Admin created.');
}

print('Current admin:');
db.users.find({ identity_number: 'admin' }).forEach(printjson);