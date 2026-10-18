-- Nuestra Casa: preparar una casa compartida para la cuenta familiar.
-- Ejecutar en Supabase SQL Editor. No borra datos de las tablas existentes.
-- Compatible con household_member o household_members.

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
  v_members_table text;
  v_member_exists boolean;
BEGIN
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE lower(email) = v_email
  ORDER BY created_at
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No encuentro fercleos@gmail.com en Authentication > Users. Comprueba que la cuenta se creó en este mismo proyecto de Supabase.';
  END IF;

  IF to_regclass('public.household_member') IS NOT NULL THEN
    v_members_table := 'household_member';
  ELSIF to_regclass('public.household_members') IS NOT NULL THEN
    v_members_table := 'household_members';
  ELSE
    RAISE EXCEPTION 'No encuentro household_member ni household_members en este proyecto de Supabase.';
  END IF;

  EXECUTE format(
    'SELECT household_id FROM public.%I WHERE user_id = $1 LIMIT 1',
    v_members_table
  ) INTO v_household_id USING v_user_id;

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

  IF NOT EXISTS (
    SELECT 1 FROM public.households
    WHERE id = v_household_id AND created_by = v_user_id
  ) THEN
    -- La cuenta ya pertenece a una casa existente; no se crea otra.
    NULL;
  END IF;

  -- Añade la cuenta como administradora si aún no es miembro.
  IF v_members_table = 'household_member' THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.household_member WHERE household_id = $1 AND user_id = $2)'
      INTO STRICT v_member_exists USING v_household_id, v_user_id;
  ELSE
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.household_members WHERE household_id = $1 AND user_id = $2)'
      INTO STRICT v_member_exists USING v_household_id, v_user_id;
  END IF;
  IF NOT v_member_exists THEN
    EXECUTE format(
      'INSERT INTO public.%I (household_id, user_id, role, permissions, joined_at) VALUES ($1, $2, %L, $3, now())',
      v_members_table, 'admin'
    ) USING v_household_id, v_user_id, '{"calendar":true,"tasks":true,"shopping":true,"meals":true}'::jsonb;
  END IF;
  RAISE NOTICE 'Nuestra Casa preparada. household_id=%', v_household_id;
END $$;
