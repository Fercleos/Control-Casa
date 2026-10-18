-- Nuestra Casa: preparar una casa compartida para la cuenta familiar.
-- Ejecutar en Supabase SQL Editor. No borra datos de las tablas existentes.
-- La tabla household_member faltaba en este proyecto; se crea con las columnas
-- que usan las funciones y políticas ya instaladas.
CREATE TABLE IF NOT EXISTS public.household_member (
  household_id uuid NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member',
  permissions jsonb NOT NULL DEFAULT '{"calendar":true,"tasks":true,"shopping":true,"meals":true}'::jsonb,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (household_id, user_id)
);
CREATE INDEX IF NOT EXISTS household_member_user_id_idx ON public.household_member(user_id);
ALTER TABLE public.household_member ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.household_member TO authenticated;
DROP POLICY IF EXISTS household_member_self_read ON public.household_member;
CREATE POLICY household_member_self_read
  ON public.household_member FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE TABLE IF NOT EXISTS public.family_app_state (
  household_id uuid PRIMARY KEY REFERENCES public.households(id) ON DELETE CASCADE,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_by uuid NOT NULL REFERENCES auth.users(id),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.family_app_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_state_read_household ON public.family_app_state;
CREATE POLICY app_state_read_household
  ON public.family_app_state FOR SELECT TO authenticated
  USING (public.is_household_member(household_id));

DROP POLICY IF EXISTS app_state_insert_household ON public.family_app_state;
CREATE POLICY app_state_insert_household
  ON public.family_app_state FOR INSERT TO authenticated
  WITH CHECK (
    public.is_household_member(household_id)
    AND updated_by = (SELECT auth.uid())
  );

DROP POLICY IF EXISTS app_state_update_household ON public.family_app_state;
CREATE POLICY app_state_update_household
  ON public.family_app_state FOR UPDATE TO authenticated
  USING (public.is_household_member(household_id))
  WITH CHECK (
    public.is_household_member(household_id)
    AND updated_by = (SELECT auth.uid())
  );

DO $$
DECLARE
  v_email text := lower(trim('fercleos@gmail.com'));
  v_user_id uuid;
  v_household_id uuid;
BEGIN
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE lower(email) = v_email
  ORDER BY created_at
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No encuentro fercleos@gmail.com en Authentication > Users. Comprueba que la cuenta se creó en este mismo proyecto de Supabase.';
  END IF;

  SELECT household_id INTO v_household_id
  FROM public.household_member
  WHERE user_id = v_user_id
  LIMIT 1;

  IF v_household_id IS NULL THEN
    SELECT id INTO v_household_id
    FROM public.households
    WHERE created_by = v_user_id
    ORDER BY created_at
    LIMIT 1;
  END IF;

  IF v_household_id IS NULL THEN
    INSERT INTO public.households (id, name, invite_code, created_by, created_at)
    VALUES (
      gen_random_uuid(),
      'Nuestra Casa',
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      v_user_id,
      now()
    )
    RETURNING id INTO v_household_id;
  END IF;

  INSERT INTO public.household_member (household_id, user_id, role, permissions, joined_at)
  VALUES (
    v_household_id, v_user_id, 'admin',
    '{"calendar":true,"tasks":true,"shopping":true,"meals":true}'::jsonb,
    now()
  )
  ON CONFLICT (household_id, user_id)
  DO UPDATE SET role = 'admin',
                permissions = EXCLUDED.permissions;

  RAISE NOTICE 'Nuestra Casa preparada. household_id=%', v_household_id;
END $$;
