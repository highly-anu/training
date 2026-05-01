-- User profiles table
-- Stores user training preferences, equipment, injuries, and schedule
CREATE TABLE IF NOT EXISTS profiles (
    user_id TEXT PRIMARY KEY,
    profile_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- User programs table
-- Stores the user's current active training program
CREATE TABLE IF NOT EXISTS user_programs (
    user_id TEXT PRIMARY KEY,
    program_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_programs ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only access their own data
CREATE POLICY "Users can view their own profile"
    ON profiles FOR SELECT
    USING (user_id = auth.uid()::text);

CREATE POLICY "Users can insert their own profile"
    ON profiles FOR INSERT
    WITH CHECK (user_id = auth.uid()::text);

CREATE POLICY "Users can update their own profile"
    ON profiles FOR UPDATE
    USING (user_id = auth.uid()::text);

CREATE POLICY "Users can view their own program"
    ON user_programs FOR SELECT
    USING (user_id = auth.uid()::text);

CREATE POLICY "Users can insert their own program"
    ON user_programs FOR INSERT
    WITH CHECK (user_id = auth.uid()::text);

CREATE POLICY "Users can update their own program"
    ON user_programs FOR UPDATE
    USING (user_id = auth.uid()::text);

-- Create indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_programs_user_id ON user_programs(user_id);
