-- Nuestra Casa: habilitar sincronización de estado compartido.
-- Antes de ejecutar:
-- 1) Crea UN usuario en Supabase > Authentication > Users (correo y contraseña).
-- 2) Sustituye REPLACE_WITH_YOUR_EMAIL por ese correo.
-- 3) Ejecuta el script completo en SQL Editor.
-- El script no borra datos de las tablas actuales.

CREATE TABLE IF NOT EXISTS public.family_app_state (
  household_id uuid PRIMARY KEY REFERENCES public.households(id) ON DELETE CASCADE,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_by uuid NOT NULL REFERENCES auth.users(id),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.family_app_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_state_read_household ON public.family_app_state;
CREATE POLICY app_state_read_household
  ON public.family_app_state
  FOR SELECT TO authenticated
  USING (public.is_household_member(household_id));

DROP POLICY IF EXISTS app_state_insert_household ON public.family_app_state;
CREATE POLICY app_state_insert_household
  ON public.family_app_state
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_household_member(household_id)
    AND updated_by = (SELECT auth.uid())
  );

DROP POLICY IF EXISTS app_state_update_household ON public.family_app_state;
CREATE POLICY app_state_update_household
  ON public.family_app_state
  FOR UPDATE TO authenticated
  USING (public.is_household_member(household_id))
  WITH CHECK (
    public.is_household_member(household_id)
    AND updated_by = (SELECT auth.uid())
  );

DO $$
DECLARE
  v_email text := lower(trim('REPLACE_WITH_YOUR_EMAIL'));
  v_user_id uuid;
  v_household_id uuid;
BEGIN
  IF v_email = 'replace_with_your_email' OR v_email = '' THEN
    RAISE EXCEPTION 'Edita REPLACE_WITH_YOUR_EMAIL y escribe el correo de la cuenta que has creado en Supabase.';
  END IF;

  SELECT id INTO v_user_id
  FROM auth.users
  WHERE lower(email) = v_email
  ORDER BY created_at
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No hay un usuario con ese correo en Authentication > Users. Créalo primero y vuelve a ejecutar.';
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

  IF NOT EXISTS (
    SELECT 1 FROM public.household_member
    WHERE household_id = v_household_id AND user_id = v_user_id
  ) THEN
    INSERT INTO public.household_member
      (household_id, user_id, role, permissions, joined_at)
    VALUES (
      v_household_id,
      v_user_id,
      'admin',
      '{"calendar":true,"tasks":true,"shopping":true,"meals":true}'::jsonb,
      now()
    );
  END IF;
END $$;

-- Comprobación final: debe salir una casa y una fila de miembro.
SELECT h.id AS household_id, h.name, hm.user_id, hm.role
FROM public.households h
JOIN public.household_member hm ON hm.household_id = h.id
WHERE h.name = 'Nuestra Casa'
ORDER BY h.created_at DESC
LIMIT 5;
