-- Match the existing submission backend's boolean acknowledgement contract.
DROP FUNCTION public.set_product_submission_display_name(uuid,text);
CREATE FUNCTION public.set_product_submission_display_name(
  p_submission_id uuid, p_display_name text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_display_name IS NULL OR char_length(btrim(p_display_name)) NOT BETWEEN 1 AND 160
     OR p_display_name ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'display name must be 1 to 160 printable characters' USING ERRCODE = '22023';
  END IF;
  UPDATE public.product_submissions SET display_name = btrim(p_display_name)
    WHERE id = p_submission_id AND user_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission unavailable' USING ERRCODE = '42501';
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.set_product_submission_display_name(uuid,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_product_submission_display_name(uuid,text)
  TO authenticated;
