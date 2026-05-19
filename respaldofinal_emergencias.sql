--
-- PostgreSQL database dump
--

\restrict lkv3ElEg6soRu7I5IiaGgvn8CdszEJBWdGiL5ay1WcP925gC71b3qIQNxOD3t8g

-- Dumped from database version 16.11
-- Dumped by pg_dump version 16.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: fn_alerta_emergencia_critica(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.fn_alerta_emergencia_critica() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO notificacion (id_evento_fk, id_usuario_destino_fk, mensaje, fecha_envio, leida)
    VALUES (
        NEW.id_evento,
        'USR-001',
        CASE 
            WHEN NEW.id_gravedad_fk = 'GRV-001' THEN '🚨 Emergencia CRÍTICA registrada: ' || NEW.id_evento || '. Requiere atención inmediata.'
            WHEN NEW.id_gravedad_fk = 'GRV-002' THEN '⚠️ Emergencia URGENTE registrada: ' || NEW.id_evento || '.'
            WHEN NEW.id_gravedad_fk = 'GRV-003' THEN '📋 Emergencia MODERADA registrada: ' || NEW.id_evento || '.'
            ELSE '📋 Emergencia registrada: ' || NEW.id_evento || '.'
        END,
        NOW(),
        false
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_alerta_emergencia_critica() OWNER TO emer_user;

--
-- Name: fn_alerta_lectura_iot(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.fn_alerta_lectura_iot() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (NEW.tipo_lectura = 'frecuencia_cardiaca' AND NEW.valor_numerico < 50) OR
       (NEW.tipo_lectura = 'saturacion_o2'       AND NEW.valor_numerico < 90) OR
       (NEW.tipo_lectura = 'temperatura'          AND NEW.valor_numerico > 39.5) THEN
        INSERT INTO alerta_iot (id_lectura_fk, mensaje, atendida)
        VALUES (NEW.id_lectura, 
                'Lectura crítica detectada: ' || NEW.tipo_lectura || ' = ' || NEW.valor_numerico,
                false);
        UPDATE lectura_iot SET alerta_generada = true WHERE id_lectura = NEW.id_lectura;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_alerta_lectura_iot() OWNER TO emer_user;

--
-- Name: fn_auditoria_evento_insert(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.fn_auditoria_evento_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO auditoria (tabla_afectada, operacion, fecha_hora)
    VALUES ('evento_emergencia', 'INSERT', NOW());
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_auditoria_evento_insert() OWNER TO emer_user;

--
-- Name: fn_auditoria_medico_insert(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.fn_auditoria_medico_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO auditoria (tabla_afectada, operacion, fecha_hora)
    VALUES ('personal_medico', 'INSERT', NOW());
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_auditoria_medico_insert() OWNER TO emer_user;

--
-- Name: fn_auditoria_medico_update(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.fn_auditoria_medico_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO auditoria (tabla_afectada, operacion, fecha_hora)
    VALUES ('personal_medico', 'UPDATE', NOW());
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_auditoria_medico_update() OWNER TO emer_user;

--
-- Name: fn_auditoria_paciente_insert(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.fn_auditoria_paciente_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO auditoria (tabla_afectada, operacion, fecha_hora)
    VALUES ('paciente', 'INSERT', NOW());
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_auditoria_paciente_insert() OWNER TO emer_user;

--
-- Name: fn_desactivar_ubicacion_anterior(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.fn_desactivar_ubicacion_anterior() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE ubicacion_personal
    SET activo = false, fecha_fin = NOW()
    WHERE id_personal_fk = NEW.id_personal_fk
      AND activo = true
      AND id_ubicacion != NEW.id_ubicacion;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_desactivar_ubicacion_anterior() OWNER TO emer_user;

--
-- Name: fn_notificar_cierre_evento(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.fn_notificar_cierre_evento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.fecha_hora_egreso IS NOT NULL AND OLD.fecha_hora_egreso IS NULL THEN
        INSERT INTO notificacion (id_evento_fk, id_usuario_destino_fk, mensaje, leida)
        SELECT NEW.id_evento, id_personal_registro_fk,
               'Evento ' || NEW.id_evento || ' ha sido cerrado.', false
        FROM evento_emergencia
        WHERE id_evento = NEW.id_evento
          AND id_personal_registro_fk IN (
              SELECT id_usuario FROM usuario_sistema
          );
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_notificar_cierre_evento() OWNER TO emer_user;

--
-- Name: fn_reducir_stock_medicamento(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.fn_reducir_stock_medicamento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE medicamento_inventario
    SET stock_actual = stock_actual - NEW.dosis_aplicada
    WHERE id_medicamento = NEW.id_medicamento_fk;

    IF (SELECT stock_actual FROM medicamento_inventario
        WHERE id_medicamento = NEW.id_medicamento_fk) < 0 THEN
        RAISE EXCEPTION 'Stock insuficiente para el medicamento: %', NEW.id_medicamento_fk;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_reducir_stock_medicamento() OWNER TO emer_user;

--
-- Name: fn_validar_signos_vitales(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.fn_validar_signos_vitales() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.frecuencia_cardiaca IS NOT NULL AND
       (NEW.frecuencia_cardiaca < 30 OR NEW.frecuencia_cardiaca > 220) THEN
        RAISE EXCEPTION 'Frecuencia cardíaca fuera de rango válido: %', NEW.frecuencia_cardiaca;
    END IF;
    IF NEW.saturacion_o2 IS NOT NULL AND
       (NEW.saturacion_o2 < 0 OR NEW.saturacion_o2 > 100) THEN
        RAISE EXCEPTION 'Saturación O2 fuera de rango válido: %', NEW.saturacion_o2;
    END IF;
    IF NEW.temperatura_c IS NOT NULL AND
       (NEW.temperatura_c < 30 OR NEW.temperatura_c > 45) THEN
        RAISE EXCEPTION 'Temperatura fuera de rango válido: %', NEW.temperatura_c;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_signos_vitales() OWNER TO emer_user;

--
-- Name: sp_alertas_iot(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_alertas_iot() RETURNS TABLE(id_alerta integer, id_lectura_fk integer, mensaje text, atendida boolean)
    LANGUAGE sql
    AS $$
    SELECT
        id_alerta,
        id_lectura_fk,
        mensaje,
        atendida
    FROM alerta_iot
    ORDER BY atendida ASC, id_alerta DESC;
$$;


ALTER FUNCTION public.sp_alertas_iot() OWNER TO emer_user;

--
-- Name: sp_cambiar_estado_medico(character varying, character varying, integer, text); Type: PROCEDURE; Schema: public; Owner: emer_user
--

CREATE PROCEDURE public.sp_cambiar_estado_medico(IN p_id_personal character varying, IN p_estado character varying, INOUT p_ok integer DEFAULT 0, INOUT p_msg text DEFAULT ''::text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE Personal_Medico SET estado = p_estado WHERE id_personal = p_id_personal;
    p_ok := 1;
    p_msg := 'Estado del médico actualizado.';
EXCEPTION
    WHEN OTHERS THEN
        p_ok := 0;
        p_msg := SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_cambiar_estado_medico(IN p_id_personal character varying, IN p_estado character varying, INOUT p_ok integer, INOUT p_msg text) OWNER TO emer_user;

--
-- Name: sp_cambiar_estado_paciente(character varying, character varying, integer, text); Type: PROCEDURE; Schema: public; Owner: emer_user
--

CREATE PROCEDURE public.sp_cambiar_estado_paciente(IN p_id_paciente character varying, IN p_estado character varying, INOUT p_ok integer DEFAULT 0, INOUT p_msg text DEFAULT ''::text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE Paciente SET estado = p_estado WHERE id_paciente = p_id_paciente;
    p_ok := 1;
    p_msg := 'Estado actualizado correctamente';
EXCEPTION WHEN OTHERS THEN
    p_ok := 0;
    p_msg := SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_cambiar_estado_paciente(IN p_id_paciente character varying, IN p_estado character varying, INOUT p_ok integer, INOUT p_msg text) OWNER TO emer_user;

--
-- Name: sp_catalogo_gravedades(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_catalogo_gravedades() RETURNS TABLE(id_gravedad character varying, nivel character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT cng.id_gravedad, cng.nivel FROM Catalogo_Nivel_Gravedad cng;
END;
$$;


ALTER FUNCTION public.sp_catalogo_gravedades() OWNER TO emer_user;

--
-- Name: sp_catalogo_hospitales(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_catalogo_hospitales() RETURNS TABLE(id_hospital character varying, nombre character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT h.id_hospital, h.nombre FROM Hospital h;
END;
$$;


ALTER FUNCTION public.sp_catalogo_hospitales() OWNER TO emer_user;

--
-- Name: sp_catalogo_municipios(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_catalogo_municipios() RETURNS TABLE(id_municipio character varying, nombre_municipio character varying)
    LANGUAGE sql
    AS $$
    SELECT id_municipio, nombre_municipio
    FROM municipio
    ORDER BY nombre_municipio;
$$;


ALTER FUNCTION public.sp_catalogo_municipios() OWNER TO emer_user;

--
-- Name: sp_catalogo_pacientes(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_catalogo_pacientes() RETURNS TABLE(id_paciente character varying, nombre_completo text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT p.id_paciente, p.nombre || ' ' || p.apellido_paterno
    FROM Paciente p ORDER BY p.apellido_paterno;
END;
$$;


ALTER FUNCTION public.sp_catalogo_pacientes() OWNER TO emer_user;

--
-- Name: sp_catalogo_personal_activo(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_catalogo_personal_activo() RETURNS TABLE(id_personal character varying, nombre_completo text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT pm.id_personal, pm.nombre || ' ' || pm.apellido_paterno
    FROM Personal_Medico pm WHERE estado = 'Activo';
END;
$$;


ALTER FUNCTION public.sp_catalogo_personal_activo() OWNER TO emer_user;

--
-- Name: sp_catalogo_salas(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_catalogo_salas() RETURNS TABLE(id_sala character varying, nombre_sala character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT ss.id_sala, ss.nombre_sala FROM Sala_Servicio ss;
END;
$$;


ALTER FUNCTION public.sp_catalogo_salas() OWNER TO emer_user;

--
-- Name: sp_catalogo_tipo_sangre(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_catalogo_tipo_sangre() RETURNS TABLE(id_tipo_sangre character varying, nombre text)
    LANGUAGE sql
    AS $$
    SELECT id_tipo_sangre, grupo || ' ' || factor_rh
    FROM catalogo_tipo_sangre
    ORDER BY grupo, factor_rh;
$$;


ALTER FUNCTION public.sp_catalogo_tipo_sangre() OWNER TO emer_user;

--
-- Name: sp_catalogo_tipos_emergencia(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_catalogo_tipos_emergencia() RETURNS TABLE(id_tipo_emergencia character varying, nombre character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT cte.id_tipo_emergencia, cte.nombre
    FROM Catalogo_Tipo_Emergencia cte WHERE activo = TRUE;
END;
$$;


ALTER FUNCTION public.sp_catalogo_tipos_emergencia() OWNER TO emer_user;

--
-- Name: sp_dashboard_stats(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_dashboard_stats(OUT total_pacientes integer, OUT total_eventos integer, OUT eventos_activos integer, OUT total_personal integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
    SELECT COUNT(*) INTO total_pacientes FROM Paciente;
    SELECT COUNT(*) INTO total_eventos FROM Evento_Emergencia;
    SELECT COUNT(*) INTO eventos_activos FROM Evento_Emergencia WHERE id_estado_evento_FK = 'EST-001';
    SELECT COUNT(*) INTO total_personal FROM Personal_Medico WHERE estado = 'Activo';
END;
$$;


ALTER FUNCTION public.sp_dashboard_stats(OUT total_pacientes integer, OUT total_eventos integer, OUT eventos_activos integer, OUT total_personal integer) OWNER TO emer_user;

--
-- Name: sp_detalle_evento(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_detalle_evento(p_id_evento character varying) RETURNS TABLE(id_evento character varying, id_paciente_fk character varying, id_tipo_emergencia_fk character varying, id_gravedad_fk character varying, id_estado_evento_fk character varying, id_hospital_fk character varying, id_sala_fk character varying, id_cama_fk character varying, fecha_hora_ingreso timestamp with time zone, fecha_hora_egreso timestamp with time zone, observaciones text, id_personal_registro_fk character varying, paciente text, tipo_emergencia character varying, gravedad character varying, color_triage character varying, estado_evento character varying, hospital character varying, sala character varying, cama character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        ee.id_evento, ee.id_paciente_FK, ee.id_tipo_emergencia_FK,
        ee.id_gravedad_FK, ee.id_estado_evento_FK, ee.id_hospital_FK,
        ee.id_sala_FK, ee.id_cama_FK,
        ee.fecha_hora_ingreso, ee.fecha_hora_egreso, ee.observaciones,
        ee.id_personal_registro_FK,
        p.nombre || ' ' || p.apellido_paterno AS paciente,
        cte.nombre AS tipo_emergencia,
        cng.nivel AS gravedad, cng.color_triage,
        cee.nombre AS estado_evento,
        h.nombre AS hospital,
        ss.nombre_sala AS sala,
        c.numero_cama AS cama
    FROM Evento_Emergencia ee
    JOIN Paciente p ON ee.id_paciente_FK = p.id_paciente
    LEFT JOIN Catalogo_Tipo_Emergencia cte ON ee.id_tipo_emergencia_FK = cte.id_tipo_emergencia
    LEFT JOIN Catalogo_Nivel_Gravedad cng ON ee.id_gravedad_FK = cng.id_gravedad
    LEFT JOIN Catalogo_Estado_Evento cee ON ee.id_estado_evento_FK = cee.id_estado_evento
    LEFT JOIN Hospital h ON ee.id_hospital_FK = h.id_hospital
    LEFT JOIN Sala_Servicio ss ON ee.id_sala_FK = ss.id_sala
    LEFT JOIN Cama c ON ee.id_cama_FK = c.id_cama
    WHERE ee.id_evento = p_id_evento;
END;
$$;


ALTER FUNCTION public.sp_detalle_evento(p_id_evento character varying) OWNER TO emer_user;

--
-- Name: sp_detalle_paciente(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_detalle_paciente(p_id_paciente character varying) RETURNS TABLE(id_paciente character varying, nombre character varying, apellido_paterno character varying, apellido_materno character varying, fecha_nacimiento date, sexo character, curp character varying, id_tipo_sangre_fk character varying, peso_kg numeric, talla_cm numeric, id_municipio_fk character varying, estado character varying, tipo_sangre text, nombre_municipio character varying, nombre_estado character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id_paciente, p.nombre, p.apellido_paterno, p.apellido_materno,
        p.fecha_nacimiento, p.sexo, p.CURP,
        p.id_tipo_sangre_FK, p.peso_kg, p.talla_cm,
        p.id_municipio_FK, p.estado,
        ts.grupo || ts.factor_rh AS tipo_sangre,
        m.nombre_municipio, e.nombre_estado
    FROM Paciente p
    LEFT JOIN Catalogo_Tipo_Sangre ts ON p.id_tipo_sangre_FK = ts.id_tipo_sangre
    LEFT JOIN Municipio m ON p.id_municipio_FK = m.id_municipio
    LEFT JOIN Estado e ON m.id_estado_FK = e.id_estado
    WHERE p.id_paciente = p_id_paciente;
END;
$$;


ALTER FUNCTION public.sp_detalle_paciente(p_id_paciente character varying) OWNER TO emer_user;

--
-- Name: sp_detalle_personal(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_detalle_personal(p_id_personal character varying) RETURNS TABLE(id_personal character varying, nombre character varying, apellido_paterno character varying, apellido_materno character varying, cedula_profesional character varying, rfc character varying, curp character varying, id_cargo_fk character varying, id_turno_fk character varying, id_hospital_fk character varying, telefono character varying, correo_institucional character varying, estado character varying, cargo character varying, turno character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        pm.id_personal, pm.nombre, pm.apellido_paterno, pm.apellido_materno,
        pm.cedula_profesional, pm.RFC, pm.CURP,
        pm.id_cargo_FK, pm.id_turno_FK, pm.id_hospital_FK,
        pm.telefono, pm.correo_institucional, pm.estado,
        cc.nombre AS cargo, ct.nombre AS turno
    FROM Personal_Medico pm
    LEFT JOIN Catalogo_Cargo cc ON pm.id_cargo_FK = cc.id_cargo
    LEFT JOIN Catalogo_Turno ct ON pm.id_turno_FK = ct.id_turno
    WHERE pm.id_personal = p_id_personal;
END;
$$;


ALTER FUNCTION public.sp_detalle_personal(p_id_personal character varying) OWNER TO emer_user;

--
-- Name: sp_editar_medico(character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, integer, text); Type: PROCEDURE; Schema: public; Owner: emer_user
--

CREATE PROCEDURE public.sp_editar_medico(IN p_id_personal character varying, IN p_nombre character varying, IN p_apellido_paterno character varying, IN p_apellido_materno character varying, IN p_cedula character varying, IN p_telefono character varying, IN p_correo character varying, IN p_id_cargo character varying, IN p_id_turno character varying, INOUT p_ok integer DEFAULT 0, INOUT p_msg text DEFAULT ''::text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE Personal_Medico SET
        nombre = p_nombre,
        apellido_paterno = p_apellido_paterno,
        apellido_materno = p_apellido_materno,
        cedula_profesional = p_cedula,
        telefono = p_telefono,
        correo_institucional = p_correo,
        id_cargo_FK = p_id_cargo,
        id_turno_FK = p_id_turno
    WHERE id_personal = p_id_personal;
    p_ok := 1;
    p_msg := 'Médico actualizado correctamente.';
EXCEPTION
    WHEN OTHERS THEN
        p_ok := 0;
        p_msg := SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_editar_medico(IN p_id_personal character varying, IN p_nombre character varying, IN p_apellido_paterno character varying, IN p_apellido_materno character varying, IN p_cedula character varying, IN p_telefono character varying, IN p_correo character varying, IN p_id_cargo character varying, IN p_id_turno character varying, INOUT p_ok integer, INOUT p_msg text) OWNER TO emer_user;

--
-- Name: sp_especialidades_personal(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_especialidades_personal(p_id_personal character varying) RETURNS TABLE(especialidad character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT ce.nombre AS especialidad
    FROM Medico_Especialidad me
    JOIN Catalogo_Especialidad ce ON me.id_especialidad_FK = ce.id_especialidad
    WHERE me.id_medico_FK = p_id_personal;
END;
$$;


ALTER FUNCTION public.sp_especialidades_personal(p_id_personal character varying) OWNER TO emer_user;

--
-- Name: sp_eventos_paciente(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_eventos_paciente(p_id_paciente character varying) RETURNS TABLE(id_evento character varying, fecha_hora_ingreso timestamp with time zone, fecha_hora_egreso timestamp with time zone, tipo_emergencia character varying, gravedad character varying, color_triage character varying, estado_evento character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        ee.id_evento, ee.fecha_hora_ingreso, ee.fecha_hora_egreso,
        cte.nombre AS tipo_emergencia,
        cng.nivel AS gravedad, cng.color_triage,
        cee.nombre AS estado_evento
    FROM Evento_Emergencia ee
    LEFT JOIN Catalogo_Tipo_Emergencia cte ON ee.id_tipo_emergencia_FK = cte.id_tipo_emergencia
    LEFT JOIN Catalogo_Nivel_Gravedad cng ON ee.id_gravedad_FK = cng.id_gravedad
    LEFT JOIN Catalogo_Estado_Evento cee ON ee.id_estado_evento_FK = cee.id_estado_evento
    WHERE ee.id_paciente_FK = p_id_paciente
    ORDER BY ee.fecha_hora_ingreso DESC;
END;
$$;


ALTER FUNCTION public.sp_eventos_paciente(p_id_paciente character varying) OWNER TO emer_user;

--
-- Name: sp_insertar_emergencia(character varying, character varying, character varying, character varying, character varying, character varying, text, character varying); Type: PROCEDURE; Schema: public; Owner: emer_user
--

CREATE PROCEDURE public.sp_insertar_emergencia(IN p_id_evento character varying, IN p_id_paciente character varying, IN p_id_tipo_emergencia character varying, IN p_id_gravedad character varying, IN p_id_hospital character varying, IN p_id_sala character varying, IN p_observaciones text, IN p_id_personal_registro character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO Evento_Emergencia (
        id_evento, id_paciente_FK, id_tipo_emergencia_FK,
        id_gravedad_FK, id_estado_evento_FK, id_hospital_FK,
        id_sala_FK, fecha_hora_ingreso, observaciones,
        id_personal_registro_FK
    ) VALUES (
        p_id_evento, p_id_paciente, p_id_tipo_emergencia,
        p_id_gravedad, 'EST-001', p_id_hospital,
        p_id_sala, CURRENT_TIMESTAMP, p_observaciones,
        p_id_personal_registro
    );
END;
$$;


ALTER PROCEDURE public.sp_insertar_emergencia(IN p_id_evento character varying, IN p_id_paciente character varying, IN p_id_tipo_emergencia character varying, IN p_id_gravedad character varying, IN p_id_hospital character varying, IN p_id_sala character varying, IN p_observaciones text, IN p_id_personal_registro character varying) OWNER TO emer_user;

--
-- Name: sp_insertar_medico(character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, integer, text); Type: PROCEDURE; Schema: public; Owner: emer_user
--

CREATE PROCEDURE public.sp_insertar_medico(IN p_id_personal character varying, IN p_nombre character varying, IN p_apellido_paterno character varying, IN p_apellido_materno character varying, IN p_cedula character varying, IN p_rfc character varying, IN p_curp character varying, IN p_id_cargo character varying, IN p_id_turno character varying, IN p_telefono character varying, IN p_correo character varying, INOUT p_ok integer DEFAULT 0, INOUT p_msg text DEFAULT ''::text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO Personal_Medico (
        id_personal, nombre, apellido_paterno, apellido_materno,
        cedula_profesional, RFC, CURP, id_cargo_FK, id_turno_FK,
        id_hospital_FK, telefono, correo_institucional
    ) VALUES (
        p_id_personal, p_nombre, p_apellido_paterno, p_apellido_materno,
        p_cedula, p_rfc, p_curp, p_id_cargo, p_id_turno,
        'HSP-001', p_telefono, p_correo
    );
    p_ok := 1;
    p_msg := 'Médico registrado correctamente.';
EXCEPTION
    WHEN unique_violation THEN
        p_ok := 0;
        p_msg := 'Ya existe un médico con ese ID, cédula, RFC o CURP.';
    WHEN OTHERS THEN
        p_ok := 0;
        p_msg := SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_insertar_medico(IN p_id_personal character varying, IN p_nombre character varying, IN p_apellido_paterno character varying, IN p_apellido_materno character varying, IN p_cedula character varying, IN p_rfc character varying, IN p_curp character varying, IN p_id_cargo character varying, IN p_id_turno character varying, IN p_telefono character varying, IN p_correo character varying, INOUT p_ok integer, INOUT p_msg text) OWNER TO emer_user;

--
-- Name: sp_insertar_paciente(character varying, character varying, character varying, character varying, date, character, character varying, character varying, numeric, numeric, character varying); Type: PROCEDURE; Schema: public; Owner: emer_user
--

CREATE PROCEDURE public.sp_insertar_paciente(IN p_id_paciente character varying, IN p_nombre character varying, IN p_apellido_paterno character varying, IN p_apellido_materno character varying, IN p_fecha_nacimiento date, IN p_sexo character, IN p_curp character varying, IN p_id_tipo_sangre character varying, IN p_peso_kg numeric, IN p_talla_cm numeric, IN p_id_municipio character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO paciente (
        id_paciente, nombre, apellido_paterno, apellido_materno,
        fecha_nacimiento, sexo, curp, id_tipo_sangre_fk,
        peso_kg, talla_cm, id_municipio_fk
    ) VALUES (
        p_id_paciente, p_nombre, p_apellido_paterno, p_apellido_materno,
        p_fecha_nacimiento, p_sexo, p_curp, p_id_tipo_sangre,
        p_peso_kg, p_talla_cm, p_id_municipio
    );
END;
$$;


ALTER PROCEDURE public.sp_insertar_paciente(IN p_id_paciente character varying, IN p_nombre character varying, IN p_apellido_paterno character varying, IN p_apellido_materno character varying, IN p_fecha_nacimiento date, IN p_sexo character, IN p_curp character varying, IN p_id_tipo_sangre character varying, IN p_peso_kg numeric, IN p_talla_cm numeric, IN p_id_municipio character varying) OWNER TO emer_user;

--
-- Name: sp_lecturas_recientes_iot(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_lecturas_recientes_iot() RETURNS TABLE(id_lectura integer, id_dispositivo_fk character varying, id_evento_fk character varying, tipo_lectura character varying, valor_numerico numeric, fecha_hora timestamp with time zone, alerta_generada boolean)
    LANGUAGE sql
    AS $$
    SELECT
        id_lectura,
        id_dispositivo_fk,
        id_evento_fk,
        tipo_lectura,
        valor_numerico,
        timestamp,
        alerta_generada
    FROM lectura_iot
    ORDER BY timestamp DESC
    LIMIT 20;
$$;


ALTER FUNCTION public.sp_lecturas_recientes_iot() OWNER TO emer_user;

--
-- Name: sp_listar_dispositivos_iot(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_listar_dispositivos_iot() RETURNS TABLE(id_dispositivo character varying, nombre character varying, tipo_dispositivo character varying, id_hospital_fk character varying, id_sala_fk character varying, estado character varying)
    LANGUAGE sql
    AS $$
    SELECT
        id_dispositivo,
        nombre,
        tipo_dispositivo,
        id_hospital_fk,
        id_sala_fk,
        estado
    FROM dispositivo_iot
    ORDER BY estado DESC, id_dispositivo;
$$;


ALTER FUNCTION public.sp_listar_dispositivos_iot() OWNER TO emer_user;

--
-- Name: sp_listar_emergencias(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_listar_emergencias() RETURNS TABLE(id_evento character varying, paciente text, tipo_emergencia character varying, gravedad character varying, color_triage character varying, estado_evento character varying, fecha_hora_ingreso timestamp with time zone, hospital character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        ee.id_evento,
        p.nombre || ' ' || p.apellido_paterno AS paciente,
        cte.nombre AS tipo_emergencia,
        cng.nivel AS gravedad,
        cng.color_triage,
        cee.nombre AS estado_evento,
        ee.fecha_hora_ingreso,
        h.nombre AS hospital
    FROM Evento_Emergencia ee
    JOIN Paciente p ON ee.id_paciente_FK = p.id_paciente
    LEFT JOIN Catalogo_Tipo_Emergencia cte ON ee.id_tipo_emergencia_FK = cte.id_tipo_emergencia
    LEFT JOIN Catalogo_Nivel_Gravedad cng ON ee.id_gravedad_FK = cng.id_gravedad
    LEFT JOIN Catalogo_Estado_Evento cee ON ee.id_estado_evento_FK = cee.id_estado_evento
    LEFT JOIN Hospital h ON ee.id_hospital_FK = h.id_hospital
    ORDER BY ee.fecha_hora_ingreso DESC;
END;
$$;


ALTER FUNCTION public.sp_listar_emergencias() OWNER TO emer_user;

--
-- Name: sp_listar_eventos(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_listar_eventos() RETURNS TABLE(id_evento character varying, paciente text, tipo_emergencia character varying, gravedad character varying, color_triage character varying, estado_evento character varying, fecha_hora_ingreso timestamp with time zone, fecha_hora_egreso timestamp with time zone, hospital character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        ee.id_evento,
        p.nombre || ' ' || p.apellido_paterno AS paciente,
        cte.nombre AS tipo_emergencia,
        cng.nivel AS gravedad, cng.color_triage,
        cee.nombre AS estado_evento,
        ee.fecha_hora_ingreso, ee.fecha_hora_egreso,
        h.nombre AS hospital
    FROM Evento_Emergencia ee
    JOIN Paciente p ON ee.id_paciente_FK = p.id_paciente
    LEFT JOIN Catalogo_Tipo_Emergencia cte ON ee.id_tipo_emergencia_FK = cte.id_tipo_emergencia
    LEFT JOIN Catalogo_Nivel_Gravedad cng ON ee.id_gravedad_FK = cng.id_gravedad
    LEFT JOIN Catalogo_Estado_Evento cee ON ee.id_estado_evento_FK = cee.id_estado_evento
    LEFT JOIN Hospital h ON ee.id_hospital_FK = h.id_hospital
    ORDER BY ee.fecha_hora_ingreso DESC;
END;
$$;


ALTER FUNCTION public.sp_listar_eventos() OWNER TO emer_user;

--
-- Name: sp_listar_pacientes(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_listar_pacientes() RETURNS TABLE(id_paciente character varying, nombre character varying, apellido_paterno character varying, apellido_materno character varying, fecha_nacimiento date, sexo character, curp character varying, tipo_sangre text, peso_kg numeric, talla_cm numeric, estado character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id_paciente, p.nombre, p.apellido_paterno, p.apellido_materno,
        p.fecha_nacimiento, p.sexo, p.CURP,
        ts.grupo || ts.factor_rh AS tipo_sangre,
        p.peso_kg, p.talla_cm, p.estado
    FROM Paciente p
    LEFT JOIN Catalogo_Tipo_Sangre ts ON p.id_tipo_sangre_FK = ts.id_tipo_sangre
    ORDER BY p.apellido_paterno;
END;
$$;


ALTER FUNCTION public.sp_listar_pacientes() OWNER TO emer_user;

--
-- Name: sp_listar_personal(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_listar_personal() RETURNS TABLE(id_personal character varying, nombre character varying, apellido_paterno character varying, apellido_materno character varying, cargo character varying, turno character varying, correo_institucional character varying, estado character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        pm.id_personal, pm.nombre, pm.apellido_paterno, pm.apellido_materno,
        cc.nombre AS cargo, ct.nombre AS turno,
        pm.correo_institucional, pm.estado
    FROM Personal_Medico pm
    LEFT JOIN Catalogo_Cargo cc ON pm.id_cargo_FK = cc.id_cargo
    LEFT JOIN Catalogo_Turno ct ON pm.id_turno_FK = ct.id_turno
    ORDER BY pm.apellido_paterno;
END;
$$;


ALTER FUNCTION public.sp_listar_personal() OWNER TO emer_user;

--
-- Name: sp_listar_usuarios(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_listar_usuarios() RETURNS TABLE(id_usuario character varying, correo character varying, personal_vinculado text, estado_cuenta character varying, ultimo_login timestamp with time zone, fecha_creacion timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        us.id_usuario, us.correo,
        pm.nombre || ' ' || pm.apellido_paterno AS personal_vinculado,
        us.estado_cuenta, us.ultimo_login, us.fecha_creacion
    FROM Usuario_Sistema us
    LEFT JOIN Personal_Medico pm ON us.id_personal_FK = pm.id_personal
    ORDER BY us.fecha_creacion DESC;
END;
$$;


ALTER FUNCTION public.sp_listar_usuarios() OWNER TO emer_user;

--
-- Name: sp_obtener_cargos(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_obtener_cargos() RETURNS TABLE(id_cargo character varying, nombre character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT cc.id_cargo, cc.nombre FROM Catalogo_Cargo cc ORDER BY cc.nombre;
END;
$$;


ALTER FUNCTION public.sp_obtener_cargos() OWNER TO emer_user;

--
-- Name: sp_obtener_especialidades(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_obtener_especialidades() RETURNS TABLE(id_especialidad character varying, nombre character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT ce.id_especialidad, ce.nombre FROM Catalogo_Especialidad ce WHERE ce.activo = TRUE ORDER BY ce.nombre;
END;
$$;


ALTER FUNCTION public.sp_obtener_especialidades() OWNER TO emer_user;

--
-- Name: sp_obtener_medico_por_id(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_obtener_medico_por_id(p_id character varying) RETURNS TABLE(id_personal character varying, nombre character varying, apellido_paterno character varying, apellido_materno character varying, cedula_profesional character varying, rfc character varying, curp character varying, id_cargo_fk character varying, id_turno_fk character varying, telefono character varying, correo_institucional character varying, estado character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT pm.id_personal, pm.nombre, pm.apellido_paterno, pm.apellido_materno,
           pm.cedula_profesional, pm.RFC, pm.CURP, pm.id_cargo_FK, pm.id_turno_FK,
           pm.telefono, pm.correo_institucional, pm.estado
    FROM Personal_Medico pm
    WHERE pm.id_personal = p_id;
END;
$$;


ALTER FUNCTION public.sp_obtener_medico_por_id(p_id character varying) OWNER TO emer_user;

--
-- Name: sp_obtener_medicos(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_obtener_medicos() RETURNS TABLE(id_personal character varying, nombre_completo text, cedula_profesional character varying, cargo character varying, turno character varying, correo_institucional character varying, estado character varying, especialidades text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        pm.id_personal,
        CONCAT(pm.nombre, ' ', pm.apellido_paterno, ' ', COALESCE(pm.apellido_materno, '')) AS nombre_completo,
        pm.cedula_profesional,
        cc.nombre AS cargo,
        ct.nombre AS turno,
        pm.correo_institucional,
        pm.estado,
        STRING_AGG(ce.nombre, ', ') AS especialidades
    FROM Personal_Medico pm
    LEFT JOIN Catalogo_Cargo cc ON pm.id_cargo_FK = cc.id_cargo
    LEFT JOIN Catalogo_Turno ct ON pm.id_turno_FK = ct.id_turno
    LEFT JOIN Medico_Especialidad me ON pm.id_personal = me.id_medico_FK
    LEFT JOIN Catalogo_Especialidad ce ON me.id_especialidad_FK = ce.id_especialidad
    GROUP BY pm.id_personal, pm.nombre, pm.apellido_paterno, pm.apellido_materno,
             pm.cedula_profesional, cc.nombre, ct.nombre, pm.correo_institucional, pm.estado
    ORDER BY pm.apellido_paterno;
END;
$$;


ALTER FUNCTION public.sp_obtener_medicos() OWNER TO emer_user;

--
-- Name: sp_obtener_turnos(); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_obtener_turnos() RETURNS TABLE(id_turno character varying, nombre character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT ct.id_turno, ct.nombre FROM Catalogo_Turno ct ORDER BY ct.nombre;
END;
$$;


ALTER FUNCTION public.sp_obtener_turnos() OWNER TO emer_user;

--
-- Name: sp_participaciones_evento(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_participaciones_evento(p_id_evento character varying) RETURNS TABLE(personal text, cargo character varying, rol character varying, hora_inicio time without time zone, hora_fin time without time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        pm.nombre || ' ' || pm.apellido_paterno AS personal,
        cc.nombre AS cargo,
        cre.nombre_rol AS rol,
        pe.hora_inicio, pe.hora_fin
    FROM Participacion_Evento pe
    JOIN Personal_Medico pm ON pe.id_personal_FK = pm.id_personal
    LEFT JOIN Catalogo_Cargo cc ON pm.id_cargo_FK = cc.id_cargo
    LEFT JOIN Catalogo_Rol_Evento cre ON pe.id_rol_evento_FK = cre.id_rol_evento
    WHERE pe.id_evento_FK = p_id_evento;
END;
$$;


ALTER FUNCTION public.sp_participaciones_evento(p_id_evento character varying) OWNER TO emer_user;

--
-- Name: sp_participaciones_personal(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_participaciones_personal(p_id_personal character varying) RETURNS TABLE(id_evento character varying, fecha_hora_ingreso timestamp with time zone, paciente text, rol character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        ee.id_evento, ee.fecha_hora_ingreso,
        p.nombre || ' ' || p.apellido_paterno AS paciente,
        cre.nombre_rol AS rol
    FROM Participacion_Evento pe
    JOIN Evento_Emergencia ee ON pe.id_evento_FK = ee.id_evento
    JOIN Paciente p ON ee.id_paciente_FK = p.id_paciente
    LEFT JOIN Catalogo_Rol_Evento cre ON pe.id_rol_evento_FK = cre.id_rol_evento
    WHERE pe.id_personal_FK = p_id_personal
    ORDER BY ee.fecha_hora_ingreso DESC
    LIMIT 10;
END;
$$;


ALTER FUNCTION public.sp_participaciones_personal(p_id_personal character varying) OWNER TO emer_user;

--
-- Name: sp_registrar_ubicacion_medico(character varying, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: emer_user
--

CREATE PROCEDURE public.sp_registrar_ubicacion_medico(IN p_id_personal character varying, IN p_id_evento character varying, IN p_id_sala character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- a) Cierra ubicación activa anterior del mismo médico
    UPDATE public.ubicacion_personal
    SET activo    = FALSE,
        fecha_fin = NOW()
    WHERE id_personal_fk = p_id_personal
      AND activo = TRUE;
 
    -- b) Registra nueva ubicación
    INSERT INTO public.ubicacion_personal
        (id_personal_fk, id_evento_fk, id_sala_fk, id_beacon_fk)
    VALUES
        (p_id_personal, p_id_evento, p_id_sala, 'DIS-003');
 
    -- c) Genera lectura en lectura_iot vinculada al beacon DIS-003
    --    Esto hace que el contador "Lecturas Cargadas" del dashboard
    --    IoT suba y quede registro del uso del beacon
    INSERT INTO public.lectura_iot
        (id_dispositivo_fk, id_evento_fk, tipo_lectura, valor_numerico, alerta_generada)
    VALUES
        ('DIS-003', p_id_evento, 'Presencia-Medico', 1, FALSE);
 
END;
$$;


ALTER PROCEDURE public.sp_registrar_ubicacion_medico(IN p_id_personal character varying, IN p_id_evento character varying, IN p_id_sala character varying) OWNER TO emer_user;

--
-- Name: sp_signos_vitales_evento(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_signos_vitales_evento(p_id_evento character varying) RETURNS TABLE(temperatura_c numeric, frecuencia_cardiaca integer, saturacion_o2 numeric, fecha_hora_toma timestamp with time zone, registrado_por text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        sv.temperatura_c, sv.frecuencia_cardiaca, sv.saturacion_o2,
        sv.fecha_hora_toma,
        pm.nombre || ' ' || pm.apellido_paterno AS registrado_por
    FROM Signos_Vitales sv
    LEFT JOIN Personal_Medico pm ON sv.id_personal_FK = pm.id_personal
    WHERE sv.id_evento_FK = p_id_evento
    ORDER BY sv.fecha_hora_toma;
END;
$$;


ALTER FUNCTION public.sp_signos_vitales_evento(p_id_evento character varying) OWNER TO emer_user;

--
-- Name: sp_tiempos_respuesta_evento(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_tiempos_respuesta_evento(p_id_evento character varying) RETURNS TABLE(nombre_momento character varying, fecha_hora timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT cma.nombre_momento, tr.fecha_hora
    FROM Tiempo_Respuesta tr
    JOIN Catalogo_Momento_Atencion cma ON tr.id_momento_FK = cma.id_momento
    WHERE tr.id_evento_FK = p_id_evento
    ORDER BY tr.fecha_hora;
END;
$$;


ALTER FUNCTION public.sp_tiempos_respuesta_evento(p_id_evento character varying) OWNER TO emer_user;

--
-- Name: sp_tutores_paciente(character varying); Type: FUNCTION; Schema: public; Owner: emer_user
--

CREATE FUNCTION public.sp_tutores_paciente(p_id_paciente character varying) RETURNS TABLE(nombre character varying, apellido_paterno character varying, telefono_principal character varying, correo character varying, parentesco character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT t.nombre, t.apellido_paterno, t.telefono_principal, t.correo,
           cp.nombre AS parentesco
    FROM Tutor_Legal t
    JOIN Paciente_Tutor pt ON t.id_tutor = pt.id_tutor_FK
    JOIN Catalogo_Parentesco cp ON pt.id_parentesco_FK = cp.id_parentesco
    WHERE pt.id_paciente_FK = p_id_paciente;
END;
$$;


ALTER FUNCTION public.sp_tutores_paciente(p_id_paciente character varying) OWNER TO emer_user;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alergia_paciente; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.alergia_paciente (
    id_alergia integer NOT NULL,
    id_paciente_fk character varying(10) NOT NULL,
    nombre_alergia character varying(100) NOT NULL,
    severidad character varying(15)
);


ALTER TABLE public.alergia_paciente OWNER TO emer_user;

--
-- Name: alergia_paciente_id_alergia_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.alergia_paciente_id_alergia_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.alergia_paciente_id_alergia_seq OWNER TO emer_user;

--
-- Name: alergia_paciente_id_alergia_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.alergia_paciente_id_alergia_seq OWNED BY public.alergia_paciente.id_alergia;


--
-- Name: alerta_iot; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.alerta_iot (
    id_alerta integer NOT NULL,
    id_lectura_fk integer NOT NULL,
    mensaje text,
    atendida boolean DEFAULT false
);


ALTER TABLE public.alerta_iot OWNER TO emer_user;

--
-- Name: alerta_iot_id_alerta_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.alerta_iot_id_alerta_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.alerta_iot_id_alerta_seq OWNER TO emer_user;

--
-- Name: alerta_iot_id_alerta_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.alerta_iot_id_alerta_seq OWNED BY public.alerta_iot.id_alerta;


--
-- Name: antecedente_medico; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.antecedente_medico (
    id_antecedente integer NOT NULL,
    id_paciente_fk character varying(10) NOT NULL,
    tipo_antecedente character varying(30),
    descripcion text NOT NULL
);


ALTER TABLE public.antecedente_medico OWNER TO emer_user;

--
-- Name: antecedente_medico_id_antecedente_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.antecedente_medico_id_antecedente_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.antecedente_medico_id_antecedente_seq OWNER TO emer_user;

--
-- Name: antecedente_medico_id_antecedente_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.antecedente_medico_id_antecedente_seq OWNED BY public.antecedente_medico.id_antecedente;


--
-- Name: auditoria; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.auditoria (
    id_auditoria integer NOT NULL,
    id_usuario_fk character varying(10),
    tabla_afectada character varying(50) NOT NULL,
    operacion character varying(10) NOT NULL,
    fecha_hora timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    ip_origen character varying(45)
);


ALTER TABLE public.auditoria OWNER TO emer_user;

--
-- Name: auditoria_id_auditoria_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.auditoria_id_auditoria_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.auditoria_id_auditoria_seq OWNER TO emer_user;

--
-- Name: auditoria_id_auditoria_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.auditoria_id_auditoria_seq OWNED BY public.auditoria.id_auditoria;


--
-- Name: cama; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.cama (
    id_cama character varying(10) NOT NULL,
    numero_cama character varying(20) NOT NULL,
    id_sala_fk character varying(10) NOT NULL,
    id_estado_cama_fk character varying(10) NOT NULL,
    tipo_cama character varying(50)
);


ALTER TABLE public.cama OWNER TO emer_user;

--
-- Name: catalogo_cargo; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_cargo (
    id_cargo character varying(10) NOT NULL,
    nombre character varying(100) NOT NULL,
    nivel_jerarquico integer,
    descripcion text
);


ALTER TABLE public.catalogo_cargo OWNER TO emer_user;

--
-- Name: catalogo_diagnostico; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_diagnostico (
    id_diagnostico character varying(10) NOT NULL,
    nombre character varying(200) NOT NULL,
    codigo_cie10 character varying(10)
);


ALTER TABLE public.catalogo_diagnostico OWNER TO emer_user;

--
-- Name: catalogo_especialidad; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_especialidad (
    id_especialidad character varying(10) NOT NULL,
    nombre character varying(100) NOT NULL,
    descripcion text,
    activo boolean DEFAULT true
);


ALTER TABLE public.catalogo_especialidad OWNER TO emer_user;

--
-- Name: catalogo_estado_cama; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_estado_cama (
    id_estado_cama character varying(10) NOT NULL,
    nombre character varying(30) NOT NULL
);


ALTER TABLE public.catalogo_estado_cama OWNER TO emer_user;

--
-- Name: catalogo_estado_egreso; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_estado_egreso (
    id_estado_egreso character varying(10) NOT NULL,
    nombre character varying(50) NOT NULL
);


ALTER TABLE public.catalogo_estado_egreso OWNER TO emer_user;

--
-- Name: catalogo_estado_evento; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_estado_evento (
    id_estado_evento character varying(10) NOT NULL,
    nombre character varying(50) NOT NULL
);


ALTER TABLE public.catalogo_estado_evento OWNER TO emer_user;

--
-- Name: catalogo_momento_atencion; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_momento_atencion (
    id_momento character varying(10) NOT NULL,
    nombre_momento character varying(50) NOT NULL
);


ALTER TABLE public.catalogo_momento_atencion OWNER TO emer_user;

--
-- Name: catalogo_nivel_gravedad; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_nivel_gravedad (
    id_gravedad character varying(10) NOT NULL,
    nivel character varying(50) NOT NULL,
    color_triage character varying(20)
);


ALTER TABLE public.catalogo_nivel_gravedad OWNER TO emer_user;

--
-- Name: catalogo_parentesco; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_parentesco (
    id_parentesco character varying(10) NOT NULL,
    nombre character varying(50) NOT NULL
);


ALTER TABLE public.catalogo_parentesco OWNER TO emer_user;

--
-- Name: catalogo_rol_evento; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_rol_evento (
    id_rol_evento character varying(10) NOT NULL,
    nombre_rol character varying(50) NOT NULL
);


ALTER TABLE public.catalogo_rol_evento OWNER TO emer_user;

--
-- Name: catalogo_tipo_documento; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_tipo_documento (
    id_tipo_documento character varying(10) NOT NULL,
    nombre character varying(50) NOT NULL
);


ALTER TABLE public.catalogo_tipo_documento OWNER TO emer_user;

--
-- Name: catalogo_tipo_emergencia; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_tipo_emergencia (
    id_tipo_emergencia character varying(10) NOT NULL,
    nombre character varying(100) NOT NULL,
    codigo_cie10 character varying(10),
    activo boolean DEFAULT true
);


ALTER TABLE public.catalogo_tipo_emergencia OWNER TO emer_user;

--
-- Name: catalogo_tipo_sangre; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_tipo_sangre (
    id_tipo_sangre character varying(10) NOT NULL,
    grupo character varying(5) NOT NULL,
    factor_rh character varying(5) NOT NULL
);


ALTER TABLE public.catalogo_tipo_sangre OWNER TO emer_user;

--
-- Name: catalogo_tratamiento; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_tratamiento (
    id_tratamiento character varying(10) NOT NULL,
    nombre character varying(150) NOT NULL,
    tipo character varying(50)
);


ALTER TABLE public.catalogo_tratamiento OWNER TO emer_user;

--
-- Name: catalogo_turno; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.catalogo_turno (
    id_turno character varying(10) NOT NULL,
    nombre character varying(50) NOT NULL,
    hora_inicio time without time zone NOT NULL,
    hora_fin time without time zone NOT NULL
);


ALTER TABLE public.catalogo_turno OWNER TO emer_user;

--
-- Name: detalle_tratamiento_medicamento; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.detalle_tratamiento_medicamento (
    id_tratamiento_fk character varying(10) NOT NULL,
    id_medicamento_fk character varying(10) NOT NULL,
    dosis_estandar character varying(50)
);


ALTER TABLE public.detalle_tratamiento_medicamento OWNER TO emer_user;

--
-- Name: dispositivo_iot; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.dispositivo_iot (
    id_dispositivo character varying(10) NOT NULL,
    nombre character varying(100) NOT NULL,
    tipo_dispositivo character varying(50) NOT NULL,
    id_hospital_fk character varying(10),
    id_sala_fk character varying(10),
    estado character varying(20) DEFAULT 'Activo'::character varying
);


ALTER TABLE public.dispositivo_iot OWNER TO emer_user;

--
-- Name: estado; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.estado (
    id_estado character varying(10) NOT NULL,
    nombre_estado character varying(100) NOT NULL,
    clave_inegi character varying(5)
);


ALTER TABLE public.estado OWNER TO emer_user;

--
-- Name: evento_diagnostico; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.evento_diagnostico (
    id_evento_fk character varying(10) NOT NULL,
    id_diagnostico_fk character varying(10) NOT NULL,
    tipo_diagnostico character varying(20)
);


ALTER TABLE public.evento_diagnostico OWNER TO emer_user;

--
-- Name: evento_emergencia; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.evento_emergencia (
    id_evento character varying(10) NOT NULL,
    id_paciente_fk character varying(10) NOT NULL,
    id_tipo_emergencia_fk character varying(10),
    id_gravedad_fk character varying(10) NOT NULL,
    id_estado_evento_fk character varying(10) NOT NULL,
    id_hospital_fk character varying(10) NOT NULL,
    id_sala_fk character varying(10),
    id_cama_fk character varying(10),
    fecha_hora_ingreso timestamp with time zone NOT NULL,
    fecha_hora_egreso timestamp with time zone,
    observaciones text,
    id_personal_registro_fk character varying(10)
);


ALTER TABLE public.evento_emergencia OWNER TO emer_user;

--
-- Name: evento_tratamiento; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.evento_tratamiento (
    id_evento_fk character varying(10) NOT NULL,
    id_tratamiento_fk character varying(10) NOT NULL,
    fecha_aplicacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.evento_tratamiento OWNER TO emer_user;

--
-- Name: hospital; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.hospital (
    id_hospital character varying(10) NOT NULL,
    nombre character varying(150) NOT NULL,
    tipo character varying(50),
    id_municipio_fk character varying(10),
    direccion text,
    nivel_atencion integer
);


ALTER TABLE public.hospital OWNER TO emer_user;

--
-- Name: lectura_iot; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.lectura_iot (
    id_lectura integer NOT NULL,
    id_dispositivo_fk character varying(10) NOT NULL,
    id_evento_fk character varying(10),
    "timestamp" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    tipo_lectura character varying(50),
    valor_numerico numeric(10,2),
    alerta_generada boolean DEFAULT false
);


ALTER TABLE public.lectura_iot OWNER TO emer_user;

--
-- Name: lectura_iot_id_lectura_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.lectura_iot_id_lectura_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lectura_iot_id_lectura_seq OWNER TO emer_user;

--
-- Name: lectura_iot_id_lectura_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.lectura_iot_id_lectura_seq OWNED BY public.lectura_iot.id_lectura;


--
-- Name: medicamento_inventario; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.medicamento_inventario (
    id_medicamento character varying(10) NOT NULL,
    nombre_generico character varying(150) NOT NULL,
    stock_actual integer DEFAULT 0,
    id_hospital_fk character varying(10) NOT NULL
);


ALTER TABLE public.medicamento_inventario OWNER TO emer_user;

--
-- Name: medico_especialidad; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.medico_especialidad (
    id_medico_fk character varying(10) NOT NULL,
    id_especialidad_fk character varying(10) NOT NULL
);


ALTER TABLE public.medico_especialidad OWNER TO emer_user;

--
-- Name: metrica_evento; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.metrica_evento (
    id_metrica integer NOT NULL,
    id_evento_fk character varying(10) NOT NULL,
    tiempo_total_evento_min integer
);


ALTER TABLE public.metrica_evento OWNER TO emer_user;

--
-- Name: metrica_evento_id_metrica_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.metrica_evento_id_metrica_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.metrica_evento_id_metrica_seq OWNER TO emer_user;

--
-- Name: metrica_evento_id_metrica_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.metrica_evento_id_metrica_seq OWNED BY public.metrica_evento.id_metrica;


--
-- Name: municipio; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.municipio (
    id_municipio character varying(10) NOT NULL,
    nombre_municipio character varying(100) NOT NULL,
    id_estado_fk character varying(10) NOT NULL
);


ALTER TABLE public.municipio OWNER TO emer_user;

--
-- Name: notificacion; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.notificacion (
    id_notificacion integer NOT NULL,
    id_evento_fk character varying(10),
    id_usuario_destino_fk character varying(10) NOT NULL,
    mensaje text,
    fecha_envio timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    leida boolean DEFAULT false
);


ALTER TABLE public.notificacion OWNER TO emer_user;

--
-- Name: notificacion_id_notificacion_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.notificacion_id_notificacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notificacion_id_notificacion_seq OWNER TO emer_user;

--
-- Name: notificacion_id_notificacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.notificacion_id_notificacion_seq OWNED BY public.notificacion.id_notificacion;


--
-- Name: paciente; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.paciente (
    id_paciente character varying(10) NOT NULL,
    nombre character varying(100) NOT NULL,
    apellido_paterno character varying(100) NOT NULL,
    apellido_materno character varying(100),
    fecha_nacimiento date NOT NULL,
    sexo character(1) NOT NULL,
    curp character varying(18),
    id_tipo_sangre_fk character varying(10),
    peso_kg numeric(5,2),
    talla_cm numeric(5,1),
    id_municipio_fk character varying(10),
    estado character varying(20) DEFAULT 'Activo'::character varying,
    CONSTRAINT chk_edad_pediatrica CHECK ((fecha_nacimiento >= (CURRENT_DATE - '18 years'::interval))),
    CONSTRAINT paciente_sexo_check CHECK ((sexo = ANY (ARRAY['M'::bpchar, 'F'::bpchar])))
);


ALTER TABLE public.paciente OWNER TO emer_user;

--
-- Name: paciente_tutor; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.paciente_tutor (
    id_paciente_fk character varying(10) NOT NULL,
    id_tutor_fk character varying(10) NOT NULL,
    id_parentesco_fk character varying(10) NOT NULL,
    es_principal boolean DEFAULT false
);


ALTER TABLE public.paciente_tutor OWNER TO emer_user;

--
-- Name: participacion_evento; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.participacion_evento (
    id_participacion integer NOT NULL,
    id_evento_fk character varying(10) NOT NULL,
    id_personal_fk character varying(10) NOT NULL,
    id_rol_evento_fk character varying(10) NOT NULL,
    hora_inicio time without time zone,
    hora_fin time without time zone
);


ALTER TABLE public.participacion_evento OWNER TO emer_user;

--
-- Name: participacion_evento_id_participacion_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.participacion_evento_id_participacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.participacion_evento_id_participacion_seq OWNER TO emer_user;

--
-- Name: participacion_evento_id_participacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.participacion_evento_id_participacion_seq OWNED BY public.participacion_evento.id_participacion;


--
-- Name: personal_medico; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.personal_medico (
    id_personal character varying(10) NOT NULL,
    nombre character varying(100) NOT NULL,
    apellido_paterno character varying(100) NOT NULL,
    apellido_materno character varying(100),
    cedula_profesional character varying(20),
    rfc character varying(13),
    curp character varying(18),
    id_cargo_fk character varying(10) NOT NULL,
    id_turno_fk character varying(10),
    id_hospital_fk character varying(10) NOT NULL,
    telefono character varying(20),
    correo_institucional character varying(150) NOT NULL,
    estado character varying(20) DEFAULT 'Activo'::character varying,
    CONSTRAINT personal_medico_estado_check CHECK (((estado)::text = ANY ((ARRAY['Activo'::character varying, 'Inactivo'::character varying])::text[])))
);


ALTER TABLE public.personal_medico OWNER TO emer_user;

--
-- Name: pulsera_nfc_paciente; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.pulsera_nfc_paciente (
    id_pulsera integer NOT NULL,
    id_paciente_fk character varying(10) NOT NULL,
    id_evento_fk character varying(10),
    codigo_nfc character varying(100),
    activa boolean DEFAULT true
);


ALTER TABLE public.pulsera_nfc_paciente OWNER TO emer_user;

--
-- Name: pulsera_nfc_paciente_id_pulsera_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.pulsera_nfc_paciente_id_pulsera_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pulsera_nfc_paciente_id_pulsera_seq OWNER TO emer_user;

--
-- Name: pulsera_nfc_paciente_id_pulsera_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.pulsera_nfc_paciente_id_pulsera_seq OWNED BY public.pulsera_nfc_paciente.id_pulsera;


--
-- Name: reporte_estadistico; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.reporte_estadistico (
    id_reporte integer NOT NULL,
    id_hospital_fk character varying(10) NOT NULL,
    periodo_inicio date NOT NULL,
    periodo_fin date NOT NULL,
    total_eventos integer
);


ALTER TABLE public.reporte_estadistico OWNER TO emer_user;

--
-- Name: reporte_estadistico_id_reporte_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.reporte_estadistico_id_reporte_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reporte_estadistico_id_reporte_seq OWNER TO emer_user;

--
-- Name: reporte_estadistico_id_reporte_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.reporte_estadistico_id_reporte_seq OWNED BY public.reporte_estadistico.id_reporte;


--
-- Name: resultado_clinico; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.resultado_clinico (
    id_resultado integer NOT NULL,
    id_evento_fk character varying(10) NOT NULL,
    id_estado_egreso_fk character varying(10) NOT NULL,
    notas_clinicas text,
    fecha_cierre timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.resultado_clinico OWNER TO emer_user;

--
-- Name: resultado_clinico_id_resultado_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.resultado_clinico_id_resultado_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.resultado_clinico_id_resultado_seq OWNER TO emer_user;

--
-- Name: resultado_clinico_id_resultado_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.resultado_clinico_id_resultado_seq OWNED BY public.resultado_clinico.id_resultado;


--
-- Name: rol_sistema; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.rol_sistema (
    id_rol_sistema character varying(10) NOT NULL,
    nombre_rol character varying(50) NOT NULL,
    nivel_acceso integer
);


ALTER TABLE public.rol_sistema OWNER TO emer_user;

--
-- Name: sala_servicio; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.sala_servicio (
    id_sala character varying(10) NOT NULL,
    nombre_sala character varying(100) NOT NULL,
    id_hospital_fk character varying(10) NOT NULL,
    tipo_sala character varying(50),
    piso character varying(10)
);


ALTER TABLE public.sala_servicio OWNER TO emer_user;

--
-- Name: signos_vitales; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.signos_vitales (
    id_signo integer NOT NULL,
    id_evento_fk character varying(10) NOT NULL,
    id_personal_fk character varying(10),
    temperatura_c numeric(4,1),
    frecuencia_cardiaca integer,
    saturacion_o2 numeric(5,2),
    fecha_hora_toma timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.signos_vitales OWNER TO emer_user;

--
-- Name: signos_vitales_id_signo_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.signos_vitales_id_signo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.signos_vitales_id_signo_seq OWNER TO emer_user;

--
-- Name: signos_vitales_id_signo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.signos_vitales_id_signo_seq OWNED BY public.signos_vitales.id_signo;


--
-- Name: tiempo_respuesta; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.tiempo_respuesta (
    id_tiempo integer NOT NULL,
    id_evento_fk character varying(10) NOT NULL,
    id_momento_fk character varying(10) NOT NULL,
    fecha_hora timestamp with time zone NOT NULL
);


ALTER TABLE public.tiempo_respuesta OWNER TO emer_user;

--
-- Name: tiempo_respuesta_id_tiempo_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.tiempo_respuesta_id_tiempo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tiempo_respuesta_id_tiempo_seq OWNER TO emer_user;

--
-- Name: tiempo_respuesta_id_tiempo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.tiempo_respuesta_id_tiempo_seq OWNED BY public.tiempo_respuesta.id_tiempo;


--
-- Name: traslado; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.traslado (
    id_traslado integer NOT NULL,
    id_evento_fk character varying(10) NOT NULL,
    id_hospital_destino_fk character varying(10) NOT NULL,
    motivo text,
    fecha_hora timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.traslado OWNER TO emer_user;

--
-- Name: traslado_id_traslado_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.traslado_id_traslado_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.traslado_id_traslado_seq OWNER TO emer_user;

--
-- Name: traslado_id_traslado_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.traslado_id_traslado_seq OWNED BY public.traslado.id_traslado;


--
-- Name: tutor_legal; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.tutor_legal (
    id_tutor character varying(10) NOT NULL,
    nombre character varying(100) NOT NULL,
    apellido_paterno character varying(100) NOT NULL,
    id_parentesco_fk character varying(10) NOT NULL,
    telefono_principal character varying(20) NOT NULL,
    correo character varying(150),
    id_tipo_documento_fk character varying(10),
    num_documento character varying(30),
    id_municipio_fk character varying(10)
);


ALTER TABLE public.tutor_legal OWNER TO emer_user;

--
-- Name: ubicacion_personal; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.ubicacion_personal (
    id_ubicacion integer NOT NULL,
    id_personal_fk character varying(10) NOT NULL,
    id_evento_fk character varying(10),
    id_sala_fk character varying(10),
    id_beacon_fk character varying(10) DEFAULT 'DIS-003'::character varying,
    fecha_inicio timestamp with time zone DEFAULT now(),
    fecha_fin timestamp with time zone,
    activo boolean DEFAULT true
);


ALTER TABLE public.ubicacion_personal OWNER TO emer_user;

--
-- Name: ubicacion_personal_id_ubicacion_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.ubicacion_personal_id_ubicacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ubicacion_personal_id_ubicacion_seq OWNER TO emer_user;

--
-- Name: ubicacion_personal_id_ubicacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.ubicacion_personal_id_ubicacion_seq OWNED BY public.ubicacion_personal.id_ubicacion;


--
-- Name: uso_medicamento_evento; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.uso_medicamento_evento (
    id_uso integer NOT NULL,
    id_evento_fk character varying(10) NOT NULL,
    id_medicamento_fk character varying(10) NOT NULL,
    dosis_aplicada numeric(10,2),
    fecha_hora timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.uso_medicamento_evento OWNER TO emer_user;

--
-- Name: uso_medicamento_evento_id_uso_seq; Type: SEQUENCE; Schema: public; Owner: emer_user
--

CREATE SEQUENCE public.uso_medicamento_evento_id_uso_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.uso_medicamento_evento_id_uso_seq OWNER TO emer_user;

--
-- Name: uso_medicamento_evento_id_uso_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: emer_user
--

ALTER SEQUENCE public.uso_medicamento_evento_id_uso_seq OWNED BY public.uso_medicamento_evento.id_uso;


--
-- Name: usuario_rol; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.usuario_rol (
    id_usuario_fk character varying(10) NOT NULL,
    id_rol_sistema_fk character varying(10) NOT NULL
);


ALTER TABLE public.usuario_rol OWNER TO emer_user;

--
-- Name: usuario_sistema; Type: TABLE; Schema: public; Owner: emer_user
--

CREATE TABLE public.usuario_sistema (
    id_usuario character varying(10) NOT NULL,
    correo character varying(150) NOT NULL,
    contrasena character varying(255) NOT NULL,
    id_personal_fk character varying(10),
    estado_cuenta character varying(20) DEFAULT 'Activo'::character varying,
    ultimo_login timestamp with time zone,
    fecha_creacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.usuario_sistema OWNER TO emer_user;

--
-- Name: v_kpi_alertas_iot; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_kpi_alertas_iot AS
 SELECT di.nombre AS dispositivo,
    di.tipo_dispositivo,
    count(ai.id_alerta) AS total_alertas,
    count(ai.id_alerta) FILTER (WHERE (ai.atendida = false)) AS alertas_pendientes,
    count(ai.id_alerta) FILTER (WHERE (ai.atendida = true)) AS alertas_atendidas
   FROM ((public.dispositivo_iot di
     LEFT JOIN public.lectura_iot li ON (((di.id_dispositivo)::text = (li.id_dispositivo_fk)::text)))
     LEFT JOIN public.alerta_iot ai ON ((li.id_lectura = ai.id_lectura_fk)))
  GROUP BY di.nombre, di.tipo_dispositivo
  ORDER BY (count(ai.id_alerta)) DESC;


ALTER VIEW public.v_kpi_alertas_iot OWNER TO emer_user;

--
-- Name: v_kpi_emergencias_por_gravedad; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_kpi_emergencias_por_gravedad AS
 SELECT cng.nivel AS gravedad,
    count(*) AS total,
    round((((count(*))::numeric * 100.0) / sum(count(*)) OVER ()), 2) AS porcentaje
   FROM (public.evento_emergencia ee
     JOIN public.catalogo_nivel_gravedad cng ON (((ee.id_gravedad_fk)::text = (cng.id_gravedad)::text)))
  GROUP BY cng.nivel
  ORDER BY (count(*)) DESC;


ALTER VIEW public.v_kpi_emergencias_por_gravedad OWNER TO emer_user;

--
-- Name: v_kpi_emergencias_por_tipo; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_kpi_emergencias_por_tipo AS
 SELECT cte.nombre AS tipo_emergencia,
    count(*) AS total,
    round((((count(*))::numeric * 100.0) / sum(count(*)) OVER ()), 2) AS porcentaje
   FROM (public.evento_emergencia ee
     JOIN public.catalogo_tipo_emergencia cte ON (((ee.id_tipo_emergencia_fk)::text = (cte.id_tipo_emergencia)::text)))
  GROUP BY cte.nombre
  ORDER BY (count(*)) DESC;


ALTER VIEW public.v_kpi_emergencias_por_tipo OWNER TO emer_user;

--
-- Name: v_kpi_medicos_top; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_kpi_medicos_top AS
 SELECT pm.id_personal,
    (((pm.nombre)::text || ' '::text) || (pm.apellido_paterno)::text) AS nombre_completo,
    cc.nombre AS cargo,
    count(pe.id_evento_fk) AS total_eventos_atendidos
   FROM ((public.personal_medico pm
     LEFT JOIN public.participacion_evento pe ON (((pm.id_personal)::text = (pe.id_personal_fk)::text)))
     LEFT JOIN public.catalogo_cargo cc ON (((pm.id_cargo_fk)::text = (cc.id_cargo)::text)))
  GROUP BY pm.id_personal, pm.nombre, pm.apellido_paterno, cc.nombre
  ORDER BY (count(pe.id_evento_fk)) DESC;


ALTER VIEW public.v_kpi_medicos_top OWNER TO emer_user;

--
-- Name: v_kpi_pacientes_por_edad; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_kpi_pacientes_por_edad AS
 SELECT
        CASE
            WHEN (date_part('year'::text, age((fecha_nacimiento)::timestamp with time zone)) < (2)::double precision) THEN '0-1 años'::text
            WHEN (date_part('year'::text, age((fecha_nacimiento)::timestamp with time zone)) < (6)::double precision) THEN '2-5 años'::text
            WHEN (date_part('year'::text, age((fecha_nacimiento)::timestamp with time zone)) < (13)::double precision) THEN '6-12 años'::text
            ELSE '13-17 años'::text
        END AS rango_edad,
    count(*) AS total_pacientes
   FROM public.paciente
  GROUP BY
        CASE
            WHEN (date_part('year'::text, age((fecha_nacimiento)::timestamp with time zone)) < (2)::double precision) THEN '0-1 años'::text
            WHEN (date_part('year'::text, age((fecha_nacimiento)::timestamp with time zone)) < (6)::double precision) THEN '2-5 años'::text
            WHEN (date_part('year'::text, age((fecha_nacimiento)::timestamp with time zone)) < (13)::double precision) THEN '6-12 años'::text
            ELSE '13-17 años'::text
        END
  ORDER BY
        CASE
            WHEN (date_part('year'::text, age((fecha_nacimiento)::timestamp with time zone)) < (2)::double precision) THEN '0-1 años'::text
            WHEN (date_part('year'::text, age((fecha_nacimiento)::timestamp with time zone)) < (6)::double precision) THEN '2-5 años'::text
            WHEN (date_part('year'::text, age((fecha_nacimiento)::timestamp with time zone)) < (13)::double precision) THEN '6-12 años'::text
            ELSE '13-17 años'::text
        END;


ALTER VIEW public.v_kpi_pacientes_por_edad OWNER TO emer_user;

--
-- Name: v_kpi_resumen_hospital; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_kpi_resumen_hospital AS
 SELECT h.nombre AS hospital,
    count(DISTINCT p.id_paciente) AS total_pacientes,
    count(DISTINCT pm.id_personal) AS total_personal_activo,
    count(DISTINCT ee.id_evento) AS total_eventos,
    count(DISTINCT ee.id_evento) FILTER (WHERE (ee.fecha_hora_egreso IS NULL)) AS eventos_activos
   FROM (((public.hospital h
     LEFT JOIN public.evento_emergencia ee ON (((h.id_hospital)::text = (ee.id_hospital_fk)::text)))
     LEFT JOIN public.paciente p ON (((ee.id_paciente_fk)::text = (p.id_paciente)::text)))
     LEFT JOIN public.personal_medico pm ON ((((h.id_hospital)::text = (pm.id_hospital_fk)::text) AND ((pm.estado)::text = 'Activo'::text))))
  GROUP BY h.nombre;


ALTER VIEW public.v_kpi_resumen_hospital OWNER TO emer_user;

--
-- Name: v_kpi_tasa_eventos_criticos; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_kpi_tasa_eventos_criticos AS
 SELECT count(*) FILTER (WHERE (((cng.nivel)::text ~~* '%Crítico%'::text) OR ((cng.nivel)::text ~~* '%Critico%'::text))) AS eventos_criticos,
    count(*) AS total_eventos,
    round((((count(*) FILTER (WHERE (((cng.nivel)::text ~~* '%Crítico%'::text) OR ((cng.nivel)::text ~~* '%Critico%'::text))))::numeric * 100.0) / (NULLIF(count(*), 0))::numeric), 2) AS tasa_criticos_pct
   FROM (public.evento_emergencia ee
     JOIN public.catalogo_nivel_gravedad cng ON (((ee.id_gravedad_fk)::text = (cng.id_gravedad)::text)));


ALTER VIEW public.v_kpi_tasa_eventos_criticos OWNER TO emer_user;

--
-- Name: v_kpi_tiempo_promedio_atencion; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_kpi_tiempo_promedio_atencion AS
 SELECT ee.id_evento,
    (((p.nombre)::text || ' '::text) || (p.apellido_paterno)::text) AS paciente,
    cte.nombre AS tipo_emergencia,
    ee.fecha_hora_ingreso,
    ee.fecha_hora_egreso,
    (EXTRACT(epoch FROM (ee.fecha_hora_egreso - ee.fecha_hora_ingreso)) / (60)::numeric) AS minutos_atencion
   FROM ((public.evento_emergencia ee
     JOIN public.paciente p ON (((ee.id_paciente_fk)::text = (p.id_paciente)::text)))
     JOIN public.catalogo_tipo_emergencia cte ON (((ee.id_tipo_emergencia_fk)::text = (cte.id_tipo_emergencia)::text)))
  WHERE (ee.fecha_hora_egreso IS NOT NULL);


ALTER VIEW public.v_kpi_tiempo_promedio_atencion OWNER TO emer_user;

--
-- Name: v_kpi_urgencias_por_turno; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_kpi_urgencias_por_turno AS
 SELECT ct.nombre AS turno,
    count(ee.id_evento) AS total_emergencias
   FROM (((public.evento_emergencia ee
     JOIN public.participacion_evento pe ON (((ee.id_evento)::text = (pe.id_evento_fk)::text)))
     JOIN public.personal_medico pm ON (((pe.id_personal_fk)::text = (pm.id_personal)::text)))
     JOIN public.catalogo_turno ct ON (((pm.id_turno_fk)::text = (ct.id_turno)::text)))
  GROUP BY ct.nombre
  ORDER BY (count(ee.id_evento)) DESC;


ALTER VIEW public.v_kpi_urgencias_por_turno OWNER TO emer_user;

--
-- Name: v_kpi_uso_medicamentos; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_kpi_uso_medicamentos AS
 SELECT mi.nombre_generico AS medicamento,
    count(ume.id_uso) AS veces_usado,
    sum(ume.dosis_aplicada) AS dosis_total_aplicada,
    mi.stock_actual AS stock_restante
   FROM (public.uso_medicamento_evento ume
     JOIN public.medicamento_inventario mi ON (((ume.id_medicamento_fk)::text = (mi.id_medicamento)::text)))
  GROUP BY mi.nombre_generico, mi.stock_actual
  ORDER BY (count(ume.id_uso)) DESC;


ALTER VIEW public.v_kpi_uso_medicamentos OWNER TO emer_user;

--
-- Name: v_ubicacion_activa_personal; Type: VIEW; Schema: public; Owner: emer_user
--

CREATE VIEW public.v_ubicacion_activa_personal AS
 SELECT u.id_ubicacion,
    u.id_personal_fk,
    (((p.nombre)::text || ' '::text) || (p.apellido_paterno)::text) AS nombre_medico,
    cc.nombre AS cargo,
    u.id_evento_fk,
    u.id_sala_fk,
    s.nombre_sala,
    u.id_beacon_fk,
    u.fecha_inicio,
    (round((EXTRACT(epoch FROM (now() - u.fecha_inicio)) / (60)::numeric)))::integer AS minutos_atendiendo
   FROM (((public.ubicacion_personal u
     JOIN public.personal_medico p ON (((p.id_personal)::text = (u.id_personal_fk)::text)))
     JOIN public.catalogo_cargo cc ON (((cc.id_cargo)::text = (p.id_cargo_fk)::text)))
     JOIN public.sala_servicio s ON (((s.id_sala)::text = (u.id_sala_fk)::text)))
  WHERE (u.activo = true);


ALTER VIEW public.v_ubicacion_activa_personal OWNER TO emer_user;

--
-- Name: alergia_paciente id_alergia; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.alergia_paciente ALTER COLUMN id_alergia SET DEFAULT nextval('public.alergia_paciente_id_alergia_seq'::regclass);


--
-- Name: alerta_iot id_alerta; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.alerta_iot ALTER COLUMN id_alerta SET DEFAULT nextval('public.alerta_iot_id_alerta_seq'::regclass);


--
-- Name: antecedente_medico id_antecedente; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.antecedente_medico ALTER COLUMN id_antecedente SET DEFAULT nextval('public.antecedente_medico_id_antecedente_seq'::regclass);


--
-- Name: auditoria id_auditoria; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.auditoria ALTER COLUMN id_auditoria SET DEFAULT nextval('public.auditoria_id_auditoria_seq'::regclass);


--
-- Name: lectura_iot id_lectura; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.lectura_iot ALTER COLUMN id_lectura SET DEFAULT nextval('public.lectura_iot_id_lectura_seq'::regclass);


--
-- Name: metrica_evento id_metrica; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.metrica_evento ALTER COLUMN id_metrica SET DEFAULT nextval('public.metrica_evento_id_metrica_seq'::regclass);


--
-- Name: notificacion id_notificacion; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.notificacion ALTER COLUMN id_notificacion SET DEFAULT nextval('public.notificacion_id_notificacion_seq'::regclass);


--
-- Name: participacion_evento id_participacion; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.participacion_evento ALTER COLUMN id_participacion SET DEFAULT nextval('public.participacion_evento_id_participacion_seq'::regclass);


--
-- Name: pulsera_nfc_paciente id_pulsera; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.pulsera_nfc_paciente ALTER COLUMN id_pulsera SET DEFAULT nextval('public.pulsera_nfc_paciente_id_pulsera_seq'::regclass);


--
-- Name: reporte_estadistico id_reporte; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.reporte_estadistico ALTER COLUMN id_reporte SET DEFAULT nextval('public.reporte_estadistico_id_reporte_seq'::regclass);


--
-- Name: resultado_clinico id_resultado; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.resultado_clinico ALTER COLUMN id_resultado SET DEFAULT nextval('public.resultado_clinico_id_resultado_seq'::regclass);


--
-- Name: signos_vitales id_signo; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.signos_vitales ALTER COLUMN id_signo SET DEFAULT nextval('public.signos_vitales_id_signo_seq'::regclass);


--
-- Name: tiempo_respuesta id_tiempo; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.tiempo_respuesta ALTER COLUMN id_tiempo SET DEFAULT nextval('public.tiempo_respuesta_id_tiempo_seq'::regclass);


--
-- Name: traslado id_traslado; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.traslado ALTER COLUMN id_traslado SET DEFAULT nextval('public.traslado_id_traslado_seq'::regclass);


--
-- Name: ubicacion_personal id_ubicacion; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.ubicacion_personal ALTER COLUMN id_ubicacion SET DEFAULT nextval('public.ubicacion_personal_id_ubicacion_seq'::regclass);


--
-- Name: uso_medicamento_evento id_uso; Type: DEFAULT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.uso_medicamento_evento ALTER COLUMN id_uso SET DEFAULT nextval('public.uso_medicamento_evento_id_uso_seq'::regclass);


--
-- Data for Name: alergia_paciente; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.alergia_paciente (id_alergia, id_paciente_fk, nombre_alergia, severidad) FROM stdin;
5	PAC-001	Penicilina	Alta
6	PAC-003	Polen	Moderada
7	PAC-005	Látex	Alta
1	PAC-001	Penicilina	Alta
2	PAC-003	Polen	Moderada
3	PAC-005	Látex	Alta
\.


--
-- Data for Name: alerta_iot; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.alerta_iot (id_alerta, id_lectura_fk, mensaje, atendida) FROM stdin;
\.


--
-- Data for Name: antecedente_medico; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.antecedente_medico (id_antecedente, id_paciente_fk, tipo_antecedente, descripcion) FROM stdin;
5	PAC-001	Quirúrgico	Apendicectomía a los 5 años
6	PAC-002	Crónico	Asma bronquial diagnosticada en 2022
7	PAC-007	Alérgico	Dermatitis atópica
1	PAC-001	Quirúrgico	Apendicectomía a los 5 años
2	PAC-002	Crónico	Asma bronquial diagnosticada en 2022
3	PAC-007	Alérgico	Dermatitis atópica
\.


--
-- Data for Name: auditoria; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.auditoria (id_auditoria, id_usuario_fk, tabla_afectada, operacion, fecha_hora, ip_origen) FROM stdin;
1	\N	evento_emergencia	INSERT	2026-05-19 05:55:49.511206+00	\N
2	\N	evento_emergencia	INSERT	2026-05-19 06:02:18.796938+00	\N
\.


--
-- Data for Name: cama; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.cama (id_cama, numero_cama, id_sala_fk, id_estado_cama_fk, tipo_cama) FROM stdin;
CMA-001	C-01	SAL-001	CAM-001	Camilla
CMA-002	C-02	SAL-001	CAM-001	Camilla
CMA-003	C-03	SAL-002	CAM-001	Cama
CMA-004	C-04	SAL-002	CAM-002	Cama
CMA-005	C-05	SAL-003	CAM-002	Cama UCI
\.


--
-- Data for Name: catalogo_cargo; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_cargo (id_cargo, nombre, nivel_jerarquico, descripcion) FROM stdin;
CAR-001	Médico Pediatra	1	Especialista en pediatría
CAR-002	Médico de Urgencias	2	Atención de emergencias
CAR-003	Enfermero/a	3	Cuidado y asistencia
CAR-004	Paramédico	4	Atención prehospitalaria
CAR-005	Jefe de Guardia	1	Responsable del turno
\.


--
-- Data for Name: catalogo_diagnostico; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_diagnostico (id_diagnostico, nombre, codigo_cie10) FROM stdin;
DIA-001	Fractura de húmero	S42
DIA-002	Broncoespasmo agudo	J98.0
DIA-003	Epilepsia no especificada	G40.9
DIA-004	Intoxicación por medicamento	T50.9
DIA-005	Deshidratación moderada	E86
\.


--
-- Data for Name: catalogo_especialidad; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_especialidad (id_especialidad, nombre, descripcion, activo) FROM stdin;
ESP-001	Pediatría General	Atención general pediátrica	t
ESP-002	Urgencias Pediátricas	Emergencias en menores	t
ESP-003	Neonatología	Atención de recién nacidos	t
ESP-004	Cirugía Pediátrica	Procedimientos quirúrgicos	t
\.


--
-- Data for Name: catalogo_estado_cama; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_estado_cama (id_estado_cama, nombre) FROM stdin;
CAM-001	Disponible
CAM-002	Ocupada
CAM-003	En Mantenimiento
\.


--
-- Data for Name: catalogo_estado_egreso; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_estado_egreso (id_estado_egreso, nombre) FROM stdin;
EGR-001	Alta Voluntaria
EGR-002	Alta Médica
EGR-003	Traslado
EGR-004	Defunción
\.


--
-- Data for Name: catalogo_estado_evento; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_estado_evento (id_estado_evento, nombre) FROM stdin;
EST-001	Activo
EST-002	En Observación
EST-003	Cerrado
EST-004	Trasladado
\.


--
-- Data for Name: catalogo_momento_atencion; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_momento_atencion (id_momento, nombre_momento) FROM stdin;
MOM-001	Llegada al hospital
MOM-002	Triage
MOM-003	Primera atención
MOM-004	Diagnóstico
MOM-005	Alta o traslado
\.


--
-- Data for Name: catalogo_nivel_gravedad; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_nivel_gravedad (id_gravedad, nivel, color_triage) FROM stdin;
GRV-001	Rojo - Crítico	rojo
GRV-002	Naranja - Urgente	naranja
GRV-003	Amarillo - Moderado	amarillo
GRV-004	Verde - Leve	verde
\.


--
-- Data for Name: catalogo_parentesco; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_parentesco (id_parentesco, nombre) FROM stdin;
PAR-001	Padre
PAR-002	Madre
PAR-003	Abuelo/a
PAR-004	Tío/a
PAR-005	Tutor Legal
\.


--
-- Data for Name: catalogo_rol_evento; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_rol_evento (id_rol_evento, nombre_rol) FROM stdin;
ROL-001	Médico Responsable
ROL-002	Médico Asistente
ROL-003	Enfermero Asignado
ROL-004	Paramédico
\.


--
-- Data for Name: catalogo_tipo_documento; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_tipo_documento (id_tipo_documento, nombre) FROM stdin;
DOC-001	INE
DOC-002	Pasaporte
DOC-003	Cédula Profesional
\.


--
-- Data for Name: catalogo_tipo_emergencia; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_tipo_emergencia (id_tipo_emergencia, nombre, codigo_cie10, activo) FROM stdin;
TEM-001	Traumatismo	S00-T98	t
TEM-002	Dificultad Respiratoria	J00-J99	t
TEM-003	Convulsiones	G40-G41	t
TEM-004	Intoxicación	T36-T65	t
TEM-005	Fiebre Alta	R50	t
TEM-006	Deshidratación	E86	t
\.


--
-- Data for Name: catalogo_tipo_sangre; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_tipo_sangre (id_tipo_sangre, grupo, factor_rh) FROM stdin;
SAN-001	O	+
SAN-002	O	-
SAN-003	A	+
SAN-004	A	-
SAN-005	B	+
SAN-006	B	-
SAN-007	AB	+
SAN-008	AB	-
\.


--
-- Data for Name: catalogo_tratamiento; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_tratamiento (id_tratamiento, nombre, tipo) FROM stdin;
TRT-001	Suero oral	Hidratación
TRT-002	Suero intravenoso	Hidratación
TRT-003	Broncodilatador	Respiratorio
TRT-004	Anticonvulsivante IV	Neurológico
TRT-005	Inmovilización y yeso	Traumatológico
\.


--
-- Data for Name: catalogo_turno; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.catalogo_turno (id_turno, nombre, hora_inicio, hora_fin) FROM stdin;
TUR-001	Matutino	07:00:00	15:00:00
TUR-002	Vespertino	15:00:00	23:00:00
TUR-003	Nocturno	23:00:00	07:00:00
\.


--
-- Data for Name: detalle_tratamiento_medicamento; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.detalle_tratamiento_medicamento (id_tratamiento_fk, id_medicamento_fk, dosis_estandar) FROM stdin;
\.


--
-- Data for Name: dispositivo_iot; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.dispositivo_iot (id_dispositivo, nombre, tipo_dispositivo, id_hospital_fk, id_sala_fk, estado) FROM stdin;
DIS-001	Monitor Cardiaco Sala URG-1	Monitor	HSP-001	SAL-001	Activo
DIS-002	Pulsioxímetro UCI-1	Sensor	HSP-001	SAL-003	Activo
DIS-003	Beacon NFC Entrada	Beacon	HSP-001	\N	Activo
DIS-004	Termómetro IoT Obs-1	Sensor	HSP-001	SAL-002	Activo
\.


--
-- Data for Name: estado; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.estado (id_estado, nombre_estado, clave_inegi) FROM stdin;
EDO-001	Nuevo León	19
EDO-002	Tamaulipas	28
EDO-003	Coahuila	05
\.


--
-- Data for Name: evento_diagnostico; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.evento_diagnostico (id_evento_fk, id_diagnostico_fk, tipo_diagnostico) FROM stdin;
EVT-001	DIA-001	Definitivo
EVT-002	DIA-002	Definitivo
EVT-003	DIA-003	Definitivo
EVT-004	DIA-005	Definitivo
EVT-006	DIA-004	Definitivo
\.


--
-- Data for Name: evento_emergencia; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.evento_emergencia (id_evento, id_paciente_fk, id_tipo_emergencia_fk, id_gravedad_fk, id_estado_evento_fk, id_hospital_fk, id_sala_fk, id_cama_fk, fecha_hora_ingreso, fecha_hora_egreso, observaciones, id_personal_registro_fk) FROM stdin;
EVT-001	PAC-001	TEM-001	GRV-002	EST-003	HSP-001	SAL-001	CMA-001	2026-01-10 08:30:00+00	2026-01-10 14:00:00+00	Caída desde bicicleta, fractura de antebrazo	PER-001
EVT-002	PAC-002	TEM-002	GRV-001	EST-003	HSP-001	SAL-003	CMA-005	2026-01-15 22:10:00+00	2026-01-17 10:00:00+00	Crisis asmática severa, requirió UCI	PER-002
EVT-003	PAC-003	TEM-003	GRV-001	EST-003	HSP-001	SAL-001	CMA-002	2026-02-03 11:45:00+00	2026-02-03 18:30:00+00	Convulsión tónico-clónica de 3 minutos	PER-001
EVT-004	PAC-004	TEM-006	GRV-003	EST-003	HSP-001	SAL-002	CMA-003	2026-02-20 16:00:00+00	2026-02-20 21:00:00+00	Deshidratación por gastroenteritis	PER-002
EVT-005	PAC-005	TEM-005	GRV-003	EST-002	HSP-001	SAL-002	CMA-004	2026-03-05 09:15:00+00	\N	Fiebre de 39.8°C sin foco aparente	PER-001
EVT-006	PAC-006	TEM-004	GRV-001	EST-003	HSP-001	SAL-003	CMA-005	2026-03-12 03:30:00+00	2026-03-13 12:00:00+00	Ingesta accidental de medicamento adulto	PER-006
EVT-007	PAC-007	TEM-001	GRV-002	EST-001	HSP-001	SAL-001	CMA-001	2026-04-01 17:20:00+00	\N	Traumatismo craneal leve por accidente	PER-002
EVT-008	PAC-008	TEM-002	GRV-001	EST-001	HSP-001	SAL-003	CMA-005	2026-04-18 05:45:00+00	\N	Bronquiolitis severa, menor de 1 año	PER-001
EVT-0050	PAC-002	TEM-003	GRV-002	EST-001	HSP-001	SAL-003	\N	2026-04-20 19:49:08.929561+00	\N	\N	PER-004
EVT-0009	PAC-007	TEM-002	GRV-002	EST-001	HSP-002	SAL-002	\N	2026-04-21 18:49:22.134765+00	\N	\N	PER-001
0021	PAC-006	TEM-002	GRV-002	EST-001	HSP-002	SAL-002	\N	2026-04-21 04:02:53.757014+00	\N	casi muere	PER-001
prueba	PAC-003	TEM-002	GRV-001	EST-002	HSP-002	SAL-003	\N	2026-05-18 23:33:05.700589+00	\N	\N	PER-004
prueba3	PAC-007	TEM-005	GRV-003	EST-001	HSP-003	SAL-002	\N	2026-05-19 00:50:47.573026+00	\N	\N	PER-002
prueba4	PAC-004	TEM-004	GRV-003	EST-001	HSP-003	SAL-004	\N	2026-05-19 00:59:08.953003+00	\N	\N	PER-002
prueba1	PAC-005	TEM-002	GRV-001	EST-002	HSP-003	SAL-002	\N	2026-05-19 00:37:06.72243+00	\N	\N	PER-003
ADT-500	PAC-005	TEM-003	GRV-001	EST-002	HSP-001	SAL-003	\N	2026-05-19 05:16:17.205812+00	\N	\N	PER-001
AVT-200	PAC-666	TEM-003	GRV-001	EST-002	HSP-002	SAL-001	\N	2026-05-19 05:38:29.767301+00	\N	\N	1w313123
AVT-100	PAC-666	TEM-003	GRV-001	EST-002	HSP-003	SAL-002	\N	2026-05-19 05:42:13.863634+00	\N	\N	PER-006
AVT-111	PAC-777	TEM-002	GRV-001	EST-002	HSP-002	SAL-002	\N	2026-05-19 05:55:49.511206+00	\N	\N	1w313123
AVT-112	PAC-777	TEM-004	GRV-001	EST-003	HSP-001	SAL-001	\N	2026-05-19 06:02:18.796938+00	2026-05-19 07:15:34.646261+00	\N	1w313123
\.


--
-- Data for Name: evento_tratamiento; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.evento_tratamiento (id_evento_fk, id_tratamiento_fk, fecha_aplicacion) FROM stdin;
EVT-001	TRT-005	2026-01-10 09:45:00+00
EVT-002	TRT-003	2026-01-15 22:25:00+00
EVT-003	TRT-004	2026-02-03 11:55:00+00
EVT-004	TRT-002	2026-02-20 16:20:00+00
EVT-006	TRT-002	2026-03-12 03:45:00+00
\.


--
-- Data for Name: hospital; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.hospital (id_hospital, nombre, tipo, id_municipio_fk, direccion, nivel_atencion) FROM stdin;
HSP-001	Cruz Roja Mexicana Monterrey	Cruz Roja	MUN-001	Alfonso Reyes 2503, Monterrey	2
HSP-002	Hospital Universitario UANL	Público	MUN-001	Francisco I. Madero S/N	3
HSP-003	Hospital Christus Muguerza	Privado	MUN-002	Hidalgo 2525, San Pedro	3
\.


--
-- Data for Name: lectura_iot; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.lectura_iot (id_lectura, id_dispositivo_fk, id_evento_fk, "timestamp", tipo_lectura, valor_numerico, alerta_generada) FROM stdin;
3	DIS-003	EVT-001	2026-05-18 00:42:26.364744+00	Presencia-Medico	1.00	f
4	DIS-003	0021	2026-05-18 00:54:03.074736+00	Presencia-Medico	1.00	f
5	DIS-003	EVT-008	2026-05-18 00:54:45.125972+00	Presencia-Medico	1.00	f
6	DIS-003	EVT-0009	2026-05-18 22:53:52.98961+00	Presencia-Medico	1.00	f
7	DIS-003	prueba	2026-05-18 23:46:29.897082+00	Presencia-Medico	1.00	f
8	DIS-003	prueba	2026-05-18 23:49:36.829741+00	Presencia-Medico	1.00	f
9	DIS-003	prueba	2026-05-19 00:02:17.449303+00	Presencia-Medico	1.00	f
10	DIS-003	prueba1	2026-05-19 00:59:37.314193+00	Presencia-Medico	1.00	f
11	DIS-003	ADT-500	2026-05-19 05:17:00.528037+00	Presencia-Medico	1.00	f
12	DIS-003	AVT-200	2026-05-19 05:38:54.470691+00	Presencia-Medico	1.00	f
13	DIS-003	AVT-100	2026-05-19 05:42:48.575582+00	Presencia-Medico	1.00	f
14	DIS-003	AVT-111	2026-05-19 05:56:17.570394+00	Presencia-Medico	1.00	f
15	DIS-003	AVT-112	2026-05-19 06:02:44.708162+00	Presencia-Medico	1.00	f
\.


--
-- Data for Name: medicamento_inventario; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.medicamento_inventario (id_medicamento, nombre_generico, stock_actual, id_hospital_fk) FROM stdin;
MED-001	Ibuprofeno 200mg	50	HSP-001
MED-002	Salbutamol inhalador	30	HSP-001
MED-003	Diazepam 5mg	20	HSP-001
MED-004	Suero fisiológico 500ml	100	HSP-001
\.


--
-- Data for Name: medico_especialidad; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.medico_especialidad (id_medico_fk, id_especialidad_fk) FROM stdin;
PER-001	ESP-001
PER-001	ESP-002
PER-002	ESP-002
PER-006	ESP-001
PER-006	ESP-003
1w313123	ESP-004
MED-010	ESP-003
MED-010	ESP-004
MED-011	ESP-002
\.


--
-- Data for Name: metrica_evento; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.metrica_evento (id_metrica, id_evento_fk, tiempo_total_evento_min) FROM stdin;
\.


--
-- Data for Name: municipio; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.municipio (id_municipio, nombre_municipio, id_estado_fk) FROM stdin;
MUN-001	Monterrey	EDO-001
MUN-002	San Pedro Garza García	EDO-001
MUN-003	Guadalupe	EDO-001
MUN-004	Apodaca	EDO-001
MUN-005	Reynosa	EDO-002
\.


--
-- Data for Name: notificacion; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.notificacion (id_notificacion, id_evento_fk, id_usuario_destino_fk, mensaje, fecha_envio, leida) FROM stdin;
1	prueba	USR-001	🚨 Emergencia CRÍTICA registrada: prueba. Requiere atención inmediata.	2026-05-18 23:33:05.700589+00	t
2	EVT-008	USR-001	🚨 Emergencia CRÍTICA registrada: EVT-008. Requiere atención inmediata.	2026-05-19 00:06:26.257836+00	f
4	prueba4	USR-001	📋 Emergencia MODERADA registrada: prueba4.	2026-05-19 00:59:08.953003+00	f
3	prueba1	USR-001	🚨 Emergencia CRÍTICA registrada: prueba1. Requiere atención inmediata.	2026-05-19 00:37:06.72243+00	t
5	ADT-500	USR-001	🚨 Emergencia CRÍTICA registrada: ADT-500. Requiere atención inmediata.	2026-05-19 05:16:17.205812+00	t
6	AVT-200	USR-001	🚨 Emergencia CRÍTICA registrada: AVT-200. Requiere atención inmediata.	2026-05-19 05:38:29.767301+00	t
7	AVT-100	USR-001	🚨 Emergencia CRÍTICA registrada: AVT-100. Requiere atención inmediata.	2026-05-19 05:42:13.863634+00	t
8	AVT-111	USR-001	🚨 Emergencia CRÍTICA registrada: AVT-111. Requiere atención inmediata.	2026-05-19 05:55:49.511206+00	t
9	AVT-112	USR-001	🚨 Emergencia CRÍTICA registrada: AVT-112. Requiere atención inmediata.	2026-05-19 06:02:18.796938+00	t
\.


--
-- Data for Name: paciente; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.paciente (id_paciente, nombre, apellido_paterno, apellido_materno, fecha_nacimiento, sexo, curp, id_tipo_sangre_fk, peso_kg, talla_cm, id_municipio_fk, estado) FROM stdin;
PAC-001	Emilio	Sánchez	Reyes	2018-03-10	M	SARE180310HNLNYML0	SAN-001	22.50	115.0	MUN-001	Activo
PAC-002	Valentina	Cruz	Moreno	2020-07-22	F	CUMO200722MNLRZL0A	SAN-003	18.00	105.0	MUN-002	Activo
PAC-003	Sebastián	Flores	García	2017-11-05	M	FOGS171105HNLLRBA2	SAN-002	28.00	125.0	MUN-003	Activo
PAC-004	Isabella	Morales	Jiménez	2022-01-15	F	MOJI220115MNLRML0B	SAN-005	12.00	88.0	MUN-001	Activo
PAC-005	Mateo	Herrera	López	2019-09-30	M	HELM190930HNLRPTZ3	SAN-001	20.00	110.0	MUN-004	Activo
PAC-006	Camila	Vega	Torres	2021-04-18	F	VETC210418MNLLRML5	SAN-007	14.50	95.0	MUN-002	Activo
PAC-008	Sofía	Jiménez	Ruiz	2023-02-10	F	JIRS230210MNLMZFA4	SAN-004	10.00	78.0	MUN-003	Activo
PAC-007	Lucas	Ramírez	Díaz	2016-08-25	M	RADL160825HNLMZCL1	SAN-003	32.00	130.0	MUN-001	Cerrado
PAC-100	Alfredo	Mateos	255	2026-05-06	F	123123123123123	SAN-003	200.00	250.0	MUN-003	Activo
PAC-666	Luis	Garcia	Toledo	2026-02-10	M	1023921048fjfbdvn	SAN-004	20.00	20.0	MUN-004	Activo
PAC-777	Jorge	lopez	mateos	2026-02-11	M	19'238102948ashdui	SAN-004	10.00	20.0	MUN-001	Activo
\.


--
-- Data for Name: paciente_tutor; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.paciente_tutor (id_paciente_fk, id_tutor_fk, id_parentesco_fk, es_principal) FROM stdin;
PAC-001	TUT-001	PAR-001	t
PAC-002	TUT-002	PAR-002	t
PAC-003	TUT-003	PAR-001	t
PAC-004	TUT-004	PAR-002	t
PAC-005	TUT-005	PAR-001	t
\.


--
-- Data for Name: participacion_evento; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.participacion_evento (id_participacion, id_evento_fk, id_personal_fk, id_rol_evento_fk, hora_inicio, hora_fin) FROM stdin;
9	EVT-001	PER-001	ROL-001	08:30:00	14:00:00
10	EVT-001	PER-003	ROL-003	08:30:00	14:00:00
11	EVT-002	PER-002	ROL-001	22:10:00	\N
12	EVT-002	PER-004	ROL-003	22:10:00	\N
13	EVT-003	PER-001	ROL-001	11:45:00	18:30:00
14	EVT-004	PER-002	ROL-001	16:00:00	21:00:00
15	EVT-005	PER-001	ROL-001	09:15:00	\N
16	EVT-006	PER-006	ROL-001	03:30:00	12:00:00
17	EVT-007	PER-002	ROL-001	17:20:00	\N
18	EVT-008	PER-001	ROL-001	05:45:00	\N
1	EVT-001	PER-001	ROL-001	08:30:00	14:00:00
2	EVT-001	PER-003	ROL-003	08:30:00	14:00:00
3	EVT-002	PER-002	ROL-001	22:10:00	\N
4	EVT-002	PER-004	ROL-003	22:10:00	\N
5	EVT-003	PER-001	ROL-001	11:45:00	18:30:00
6	EVT-004	PER-002	ROL-001	16:00:00	21:00:00
7	EVT-005	PER-001	ROL-001	09:15:00	\N
8	EVT-006	PER-006	ROL-001	03:30:00	12:00:00
\.


--
-- Data for Name: personal_medico; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.personal_medico (id_personal, nombre, apellido_paterno, apellido_materno, cedula_profesional, rfc, curp, id_cargo_fk, id_turno_fk, id_hospital_fk, telefono, correo_institucional, estado) FROM stdin;
PER-001	Carlos	Ramírez	Lozano	CED-001	RFC-PER001	CURP-PER001	CAR-001	TUR-001	HSP-001	8112001001	c.ramirez@cruzroja.mx	Activo
PER-002	Laura	González	Vega	CED-002	RFC-PER002	CURP-PER002	CAR-002	TUR-002	HSP-001	8112001002	l.gonzalez@cruzroja.mx	Activo
PER-003	Miguel	Torres	Salas	CED-003	RFC-PER003	CURP-PER003	CAR-003	TUR-001	HSP-001	8112001003	m.torres@cruzroja.mx	Activo
PER-004	Ana	Martínez	Ruiz	CED-004	RFC-PER004	CURP-PER004	CAR-003	TUR-003	HSP-001	8112001004	a.martinez@cruzroja.mx	Activo
PER-006	Sofía	López	Morales	CED-006	RFC-PER006	CURP-PER006	CAR-005	TUR-001	HSP-001	8112001006	s.lopez@cruzroja.mx	Activo
PER-007	Jorge	Díaz	Peña	CED-007	RFC-PER007	CURP-PER007	CAR-001	TUR-003	HSP-001	8112001007	j.diaz@cruzroja.mx	Inactivo
1w313123	alejandrin	Cazares	escobedo	1313123	1231231231	123132231	CAR-002	TUR-003	HSP-001	12312313	adasdsdad@gmail.com	Activo
PER-005	Roberto	Herrera	Cruz	CED-005	RFC-PER005	CURP-PER005	CAR-004	TUR-002	HSP-001	8112001005	r.herrera@cruzroja.mx	Inactivo
MED-010	Roberuto	Guerra	Martinez	CED-008	FZYU600614IH8	DBCX530301MTCHZF46	CAR-005	TUR-001	HSP-001	528112345678	roberuto.guerra@gmail.com	Activo
MED-011	Jorgue	Torres	Tamez	CED-009	FZYU600614IH9	DBCX530301MTCHZF47	CAR-004	TUR-003	HSP-001	528112345679	diego.Torres@gmail.com	Activo
\.


--
-- Data for Name: pulsera_nfc_paciente; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.pulsera_nfc_paciente (id_pulsera, id_paciente_fk, id_evento_fk, codigo_nfc, activa) FROM stdin;
1	PAC-001	EVT-001	NFC-PAC001-EVT001	f
2	PAC-002	EVT-002	NFC-PAC002-EVT002	f
3	PAC-007	EVT-007	NFC-PAC007-EVT007	t
4	PAC-008	EVT-008	NFC-PAC008-EVT008	t
\.


--
-- Data for Name: reporte_estadistico; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.reporte_estadistico (id_reporte, id_hospital_fk, periodo_inicio, periodo_fin, total_eventos) FROM stdin;
\.


--
-- Data for Name: resultado_clinico; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.resultado_clinico (id_resultado, id_evento_fk, id_estado_egreso_fk, notas_clinicas, fecha_cierre) FROM stdin;
1	EVT-001	EGR-002	Alta médica con inmovilización, seguimiento en 7 días	2026-04-20 19:47:06.788473
2	EVT-002	EGR-002	Mejoría progresiva, alta con broncodilatador domiciliario	2026-04-20 19:47:06.788473
3	EVT-003	EGR-002	Sin nuevas crisis, alta con anticonvulsivante	2026-04-20 19:47:06.788473
4	EVT-004	EGR-002	Hidratación completa, tolerando vía oral	2026-04-20 19:47:06.788473
5	EVT-006	EGR-002	Estable tras lavado gástrico y observación	2026-04-20 19:47:06.788473
\.


--
-- Data for Name: rol_sistema; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.rol_sistema (id_rol_sistema, nombre_rol, nivel_acceso) FROM stdin;
ROL-SIS-1	Administrador	1
ROL-SIS-2	Médico	2
ROL-SIS-3	Enfermero	3
\.


--
-- Data for Name: sala_servicio; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.sala_servicio (id_sala, nombre_sala, id_hospital_fk, tipo_sala, piso) FROM stdin;
SAL-001	Urgencias Pediátricas	HSP-001	Urgencias	PB
SAL-002	Observación	HSP-001	Observación	PB
SAL-003	Terapia Intensiva	HSP-001	UCI	1
SAL-004	Quirófano	HSP-001	Quirúrgica	2
\.


--
-- Data for Name: signos_vitales; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.signos_vitales (id_signo, id_evento_fk, id_personal_fk, temperatura_c, frecuencia_cardiaca, saturacion_o2, fecha_hora_toma) FROM stdin;
10	EVT-001	PER-003	36.8	95	98.50	2026-01-10 08:45:00+00
11	EVT-002	PER-004	37.5	140	88.00	2026-01-15 22:20:00+00
12	EVT-002	PER-004	37.2	120	93.00	2026-01-16 06:00:00+00
13	EVT-003	PER-003	38.1	110	96.00	2026-02-03 11:50:00+00
14	EVT-004	PER-003	37.9	105	97.50	2026-02-20 16:15:00+00
15	EVT-005	PER-003	39.8	118	97.00	2026-03-05 09:30:00+00
16	EVT-006	PER-004	36.5	130	91.00	2026-03-12 03:40:00+00
17	EVT-007	PER-003	36.9	88	99.00	2026-04-01 17:30:00+00
18	EVT-008	PER-004	38.5	145	85.00	2026-04-18 05:50:00+00
1	EVT-001	PER-003	36.8	95	98.50	2026-01-10 08:45:00+00
2	EVT-002	PER-004	37.5	140	88.00	2026-01-15 22:20:00+00
3	EVT-002	PER-004	37.2	120	93.00	2026-01-16 06:00:00+00
4	EVT-003	PER-003	38.1	110	96.00	2026-02-03 11:50:00+00
5	EVT-004	PER-003	37.9	105	97.50	2026-02-20 16:15:00+00
6	EVT-005	PER-003	39.8	118	97.00	2026-03-05 09:30:00+00
7	EVT-006	PER-004	36.5	130	91.00	2026-03-12 03:40:00+00
8	EVT-007	PER-003	36.9	88	99.00	2026-04-01 17:30:00+00
9	EVT-008	PER-004	38.5	145	85.00	2026-04-18 05:50:00+00
\.


--
-- Data for Name: tiempo_respuesta; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.tiempo_respuesta (id_tiempo, id_evento_fk, id_momento_fk, fecha_hora) FROM stdin;
7	EVT-001	MOM-001	2026-01-10 08:30:00+00
8	EVT-001	MOM-002	2026-01-10 08:35:00+00
9	EVT-001	MOM-003	2026-01-10 08:45:00+00
10	EVT-001	MOM-004	2026-01-10 09:30:00+00
11	EVT-001	MOM-005	2026-01-10 14:00:00+00
12	EVT-002	MOM-001	2026-01-15 22:10:00+00
13	EVT-002	MOM-002	2026-01-15 22:12:00+00
14	EVT-002	MOM-003	2026-01-15 22:18:00+00
15	EVT-003	MOM-001	2026-02-03 11:45:00+00
16	EVT-003	MOM-002	2026-02-03 11:47:00+00
17	EVT-003	MOM-003	2026-02-03 11:52:00+00
1	EVT-001	MOM-001	2026-01-10 08:30:00+00
2	EVT-001	MOM-002	2026-01-10 08:35:00+00
3	EVT-001	MOM-003	2026-01-10 08:45:00+00
4	EVT-001	MOM-004	2026-01-10 09:30:00+00
5	EVT-001	MOM-005	2026-01-10 14:00:00+00
6	EVT-002	MOM-001	2026-01-15 22:10:00+00
\.


--
-- Data for Name: traslado; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.traslado (id_traslado, id_evento_fk, id_hospital_destino_fk, motivo, fecha_hora) FROM stdin;
\.


--
-- Data for Name: tutor_legal; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.tutor_legal (id_tutor, nombre, apellido_paterno, id_parentesco_fk, telefono_principal, correo, id_tipo_documento_fk, num_documento, id_municipio_fk) FROM stdin;
TUT-001	Roberto	Sánchez	PAR-001	8111001001	r.sanchez@email.com	DOC-001	INE-001	MUN-001
TUT-002	Patricia	Cruz	PAR-002	8111001002	p.cruz@email.com	DOC-001	INE-002	MUN-002
TUT-003	Fernando	Flores	PAR-001	8111001003	f.flores@email.com	DOC-001	INE-003	MUN-003
TUT-004	María	Morales	PAR-002	8111001004	m.morales@email.com	DOC-001	INE-004	MUN-001
TUT-005	Eduardo	Herrera	PAR-001	8111001005	e.herrera@email.com	DOC-001	INE-005	MUN-004
\.


--
-- Data for Name: ubicacion_personal; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.ubicacion_personal (id_ubicacion, id_personal_fk, id_evento_fk, id_sala_fk, id_beacon_fk, fecha_inicio, fecha_fin, activo) FROM stdin;
1	PER-001	EVT-001	SAL-001	DIS-003	2026-05-18 00:42:26.364744+00	2026-05-18 00:54:03.074736+00	f
3	PER-002	EVT-008	SAL-001	DIS-003	2026-05-18 00:54:45.125972+00	\N	t
4	PER-004	EVT-0009	SAL-001	DIS-003	2026-05-18 22:53:52.98961+00	2026-05-18 23:49:36.829741+00	f
5	PER-003	prueba	SAL-001	DIS-003	2026-05-18 23:46:29.897082+00	2026-05-19 00:02:17.449303+00	f
8	PER-005	prueba1	SAL-001	DIS-003	2026-05-19 00:59:37.314193+00	\N	t
7	PER-003	prueba	SAL-001	DIS-003	2026-05-19 00:02:17.449303+00	2026-05-19 05:17:00.528037+00	f
9	PER-003	ADT-500	SAL-001	DIS-003	2026-05-19 05:17:00.528037+00	2026-05-19 05:38:54.470691+00	f
10	PER-003	AVT-200	SAL-001	DIS-003	2026-05-19 05:38:54.470691+00	\N	t
11	MED-010	AVT-100	SAL-001	DIS-003	2026-05-19 05:42:48.575582+00	\N	t
2	PER-001	0021	SAL-001	DIS-003	2026-05-18 00:54:03.074736+00	2026-05-19 05:56:17.570394+00	f
12	PER-001	AVT-111	SAL-001	DIS-003	2026-05-19 05:56:17.570394+00	\N	t
6	PER-004	prueba	SAL-001	DIS-003	2026-05-18 23:49:36.829741+00	2026-05-19 06:02:44.708162+00	f
13	PER-004	AVT-112	SAL-001	DIS-003	2026-05-19 06:02:44.708162+00	\N	t
\.


--
-- Data for Name: uso_medicamento_evento; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.uso_medicamento_evento (id_uso, id_evento_fk, id_medicamento_fk, dosis_aplicada, fecha_hora) FROM stdin;
\.


--
-- Data for Name: usuario_rol; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.usuario_rol (id_usuario_fk, id_rol_sistema_fk) FROM stdin;
USR-001	ROL-SIS-1
USR-002	ROL-SIS-2
USR-003	ROL-SIS-2
\.


--
-- Data for Name: usuario_sistema; Type: TABLE DATA; Schema: public; Owner: emer_user
--

COPY public.usuario_sistema (id_usuario, correo, contrasena, id_personal_fk, estado_cuenta, ultimo_login, fecha_creacion) FROM stdin;
USR-001	admin@cruzroja.mx	1234	PER-006	Activo	\N	2026-04-20 19:47:06.752565+00
USR-002	c.ramirez@cruzroja.mx	1234	PER-001	Activo	\N	2026-04-20 19:47:06.752565+00
USR-003	l.gonzalez@cruzroja.mx	1234	PER-002	Activo	\N	2026-04-20 19:47:06.752565+00
\.


--
-- Name: alergia_paciente_id_alergia_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.alergia_paciente_id_alergia_seq', 7, true);


--
-- Name: alerta_iot_id_alerta_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.alerta_iot_id_alerta_seq', 1, true);


--
-- Name: antecedente_medico_id_antecedente_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.antecedente_medico_id_antecedente_seq', 7, true);


--
-- Name: auditoria_id_auditoria_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.auditoria_id_auditoria_seq', 2, true);


--
-- Name: lectura_iot_id_lectura_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.lectura_iot_id_lectura_seq', 15, true);


--
-- Name: metrica_evento_id_metrica_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.metrica_evento_id_metrica_seq', 1, false);


--
-- Name: notificacion_id_notificacion_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.notificacion_id_notificacion_seq', 10, true);


--
-- Name: participacion_evento_id_participacion_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.participacion_evento_id_participacion_seq', 18, true);


--
-- Name: pulsera_nfc_paciente_id_pulsera_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.pulsera_nfc_paciente_id_pulsera_seq', 4, true);


--
-- Name: reporte_estadistico_id_reporte_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.reporte_estadistico_id_reporte_seq', 1, false);


--
-- Name: resultado_clinico_id_resultado_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.resultado_clinico_id_resultado_seq', 5, true);


--
-- Name: signos_vitales_id_signo_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.signos_vitales_id_signo_seq', 18, true);


--
-- Name: tiempo_respuesta_id_tiempo_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.tiempo_respuesta_id_tiempo_seq', 17, true);


--
-- Name: traslado_id_traslado_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.traslado_id_traslado_seq', 1, false);


--
-- Name: ubicacion_personal_id_ubicacion_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.ubicacion_personal_id_ubicacion_seq', 13, true);


--
-- Name: uso_medicamento_evento_id_uso_seq; Type: SEQUENCE SET; Schema: public; Owner: emer_user
--

SELECT pg_catalog.setval('public.uso_medicamento_evento_id_uso_seq', 1, false);


--
-- Name: alergia_paciente alergia_paciente_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.alergia_paciente
    ADD CONSTRAINT alergia_paciente_pkey PRIMARY KEY (id_alergia);


--
-- Name: alerta_iot alerta_iot_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.alerta_iot
    ADD CONSTRAINT alerta_iot_pkey PRIMARY KEY (id_alerta);


--
-- Name: antecedente_medico antecedente_medico_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.antecedente_medico
    ADD CONSTRAINT antecedente_medico_pkey PRIMARY KEY (id_antecedente);


--
-- Name: auditoria auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_pkey PRIMARY KEY (id_auditoria);


--
-- Name: cama cama_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.cama
    ADD CONSTRAINT cama_pkey PRIMARY KEY (id_cama);


--
-- Name: catalogo_cargo catalogo_cargo_nombre_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_cargo
    ADD CONSTRAINT catalogo_cargo_nombre_key UNIQUE (nombre);


--
-- Name: catalogo_cargo catalogo_cargo_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_cargo
    ADD CONSTRAINT catalogo_cargo_pkey PRIMARY KEY (id_cargo);


--
-- Name: catalogo_diagnostico catalogo_diagnostico_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_diagnostico
    ADD CONSTRAINT catalogo_diagnostico_pkey PRIMARY KEY (id_diagnostico);


--
-- Name: catalogo_especialidad catalogo_especialidad_nombre_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_especialidad
    ADD CONSTRAINT catalogo_especialidad_nombre_key UNIQUE (nombre);


--
-- Name: catalogo_especialidad catalogo_especialidad_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_especialidad
    ADD CONSTRAINT catalogo_especialidad_pkey PRIMARY KEY (id_especialidad);


--
-- Name: catalogo_estado_cama catalogo_estado_cama_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_estado_cama
    ADD CONSTRAINT catalogo_estado_cama_pkey PRIMARY KEY (id_estado_cama);


--
-- Name: catalogo_estado_egreso catalogo_estado_egreso_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_estado_egreso
    ADD CONSTRAINT catalogo_estado_egreso_pkey PRIMARY KEY (id_estado_egreso);


--
-- Name: catalogo_estado_evento catalogo_estado_evento_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_estado_evento
    ADD CONSTRAINT catalogo_estado_evento_pkey PRIMARY KEY (id_estado_evento);


--
-- Name: catalogo_momento_atencion catalogo_momento_atencion_nombre_momento_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_momento_atencion
    ADD CONSTRAINT catalogo_momento_atencion_nombre_momento_key UNIQUE (nombre_momento);


--
-- Name: catalogo_momento_atencion catalogo_momento_atencion_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_momento_atencion
    ADD CONSTRAINT catalogo_momento_atencion_pkey PRIMARY KEY (id_momento);


--
-- Name: catalogo_nivel_gravedad catalogo_nivel_gravedad_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_nivel_gravedad
    ADD CONSTRAINT catalogo_nivel_gravedad_pkey PRIMARY KEY (id_gravedad);


--
-- Name: catalogo_parentesco catalogo_parentesco_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_parentesco
    ADD CONSTRAINT catalogo_parentesco_pkey PRIMARY KEY (id_parentesco);


--
-- Name: catalogo_rol_evento catalogo_rol_evento_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_rol_evento
    ADD CONSTRAINT catalogo_rol_evento_pkey PRIMARY KEY (id_rol_evento);


--
-- Name: catalogo_tipo_documento catalogo_tipo_documento_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_tipo_documento
    ADD CONSTRAINT catalogo_tipo_documento_pkey PRIMARY KEY (id_tipo_documento);


--
-- Name: catalogo_tipo_emergencia catalogo_tipo_emergencia_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_tipo_emergencia
    ADD CONSTRAINT catalogo_tipo_emergencia_pkey PRIMARY KEY (id_tipo_emergencia);


--
-- Name: catalogo_tipo_sangre catalogo_tipo_sangre_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_tipo_sangre
    ADD CONSTRAINT catalogo_tipo_sangre_pkey PRIMARY KEY (id_tipo_sangre);


--
-- Name: catalogo_tratamiento catalogo_tratamiento_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_tratamiento
    ADD CONSTRAINT catalogo_tratamiento_pkey PRIMARY KEY (id_tratamiento);


--
-- Name: catalogo_turno catalogo_turno_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.catalogo_turno
    ADD CONSTRAINT catalogo_turno_pkey PRIMARY KEY (id_turno);


--
-- Name: detalle_tratamiento_medicamento detalle_tratamiento_medicamento_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.detalle_tratamiento_medicamento
    ADD CONSTRAINT detalle_tratamiento_medicamento_pkey PRIMARY KEY (id_tratamiento_fk, id_medicamento_fk);


--
-- Name: dispositivo_iot dispositivo_iot_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.dispositivo_iot
    ADD CONSTRAINT dispositivo_iot_pkey PRIMARY KEY (id_dispositivo);


--
-- Name: estado estado_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.estado
    ADD CONSTRAINT estado_pkey PRIMARY KEY (id_estado);


--
-- Name: evento_diagnostico evento_diagnostico_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_diagnostico
    ADD CONSTRAINT evento_diagnostico_pkey PRIMARY KEY (id_evento_fk, id_diagnostico_fk);


--
-- Name: evento_emergencia evento_emergencia_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_emergencia
    ADD CONSTRAINT evento_emergencia_pkey PRIMARY KEY (id_evento);


--
-- Name: evento_tratamiento evento_tratamiento_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_tratamiento
    ADD CONSTRAINT evento_tratamiento_pkey PRIMARY KEY (id_evento_fk, id_tratamiento_fk);


--
-- Name: hospital hospital_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.hospital
    ADD CONSTRAINT hospital_pkey PRIMARY KEY (id_hospital);


--
-- Name: lectura_iot lectura_iot_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.lectura_iot
    ADD CONSTRAINT lectura_iot_pkey PRIMARY KEY (id_lectura);


--
-- Name: medicamento_inventario medicamento_inventario_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.medicamento_inventario
    ADD CONSTRAINT medicamento_inventario_pkey PRIMARY KEY (id_medicamento);


--
-- Name: medico_especialidad medico_especialidad_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.medico_especialidad
    ADD CONSTRAINT medico_especialidad_pkey PRIMARY KEY (id_medico_fk, id_especialidad_fk);


--
-- Name: metrica_evento metrica_evento_id_evento_fk_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.metrica_evento
    ADD CONSTRAINT metrica_evento_id_evento_fk_key UNIQUE (id_evento_fk);


--
-- Name: metrica_evento metrica_evento_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.metrica_evento
    ADD CONSTRAINT metrica_evento_pkey PRIMARY KEY (id_metrica);


--
-- Name: municipio municipio_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.municipio
    ADD CONSTRAINT municipio_pkey PRIMARY KEY (id_municipio);


--
-- Name: notificacion notificacion_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.notificacion
    ADD CONSTRAINT notificacion_pkey PRIMARY KEY (id_notificacion);


--
-- Name: paciente paciente_curp_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.paciente
    ADD CONSTRAINT paciente_curp_key UNIQUE (curp);


--
-- Name: paciente paciente_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.paciente
    ADD CONSTRAINT paciente_pkey PRIMARY KEY (id_paciente);


--
-- Name: paciente_tutor paciente_tutor_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.paciente_tutor
    ADD CONSTRAINT paciente_tutor_pkey PRIMARY KEY (id_paciente_fk, id_tutor_fk);


--
-- Name: participacion_evento participacion_evento_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.participacion_evento
    ADD CONSTRAINT participacion_evento_pkey PRIMARY KEY (id_participacion);


--
-- Name: personal_medico personal_medico_cedula_profesional_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.personal_medico
    ADD CONSTRAINT personal_medico_cedula_profesional_key UNIQUE (cedula_profesional);


--
-- Name: personal_medico personal_medico_correo_institucional_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.personal_medico
    ADD CONSTRAINT personal_medico_correo_institucional_key UNIQUE (correo_institucional);


--
-- Name: personal_medico personal_medico_curp_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.personal_medico
    ADD CONSTRAINT personal_medico_curp_key UNIQUE (curp);


--
-- Name: personal_medico personal_medico_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.personal_medico
    ADD CONSTRAINT personal_medico_pkey PRIMARY KEY (id_personal);


--
-- Name: personal_medico personal_medico_rfc_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.personal_medico
    ADD CONSTRAINT personal_medico_rfc_key UNIQUE (rfc);


--
-- Name: pulsera_nfc_paciente pulsera_nfc_paciente_codigo_nfc_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.pulsera_nfc_paciente
    ADD CONSTRAINT pulsera_nfc_paciente_codigo_nfc_key UNIQUE (codigo_nfc);


--
-- Name: pulsera_nfc_paciente pulsera_nfc_paciente_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.pulsera_nfc_paciente
    ADD CONSTRAINT pulsera_nfc_paciente_pkey PRIMARY KEY (id_pulsera);


--
-- Name: reporte_estadistico reporte_estadistico_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.reporte_estadistico
    ADD CONSTRAINT reporte_estadistico_pkey PRIMARY KEY (id_reporte);


--
-- Name: resultado_clinico resultado_clinico_id_evento_fk_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.resultado_clinico
    ADD CONSTRAINT resultado_clinico_id_evento_fk_key UNIQUE (id_evento_fk);


--
-- Name: resultado_clinico resultado_clinico_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.resultado_clinico
    ADD CONSTRAINT resultado_clinico_pkey PRIMARY KEY (id_resultado);


--
-- Name: rol_sistema rol_sistema_nombre_rol_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.rol_sistema
    ADD CONSTRAINT rol_sistema_nombre_rol_key UNIQUE (nombre_rol);


--
-- Name: rol_sistema rol_sistema_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.rol_sistema
    ADD CONSTRAINT rol_sistema_pkey PRIMARY KEY (id_rol_sistema);


--
-- Name: sala_servicio sala_servicio_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.sala_servicio
    ADD CONSTRAINT sala_servicio_pkey PRIMARY KEY (id_sala);


--
-- Name: signos_vitales signos_vitales_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.signos_vitales
    ADD CONSTRAINT signos_vitales_pkey PRIMARY KEY (id_signo);


--
-- Name: tiempo_respuesta tiempo_respuesta_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.tiempo_respuesta
    ADD CONSTRAINT tiempo_respuesta_pkey PRIMARY KEY (id_tiempo);


--
-- Name: traslado traslado_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.traslado
    ADD CONSTRAINT traslado_pkey PRIMARY KEY (id_traslado);


--
-- Name: tutor_legal tutor_legal_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.tutor_legal
    ADD CONSTRAINT tutor_legal_pkey PRIMARY KEY (id_tutor);


--
-- Name: ubicacion_personal ubicacion_personal_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.ubicacion_personal
    ADD CONSTRAINT ubicacion_personal_pkey PRIMARY KEY (id_ubicacion);


--
-- Name: cama uq_cama_sala; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.cama
    ADD CONSTRAINT uq_cama_sala UNIQUE (id_sala_fk, numero_cama);


--
-- Name: uso_medicamento_evento uso_medicamento_evento_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.uso_medicamento_evento
    ADD CONSTRAINT uso_medicamento_evento_pkey PRIMARY KEY (id_uso);


--
-- Name: usuario_rol usuario_rol_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT usuario_rol_pkey PRIMARY KEY (id_usuario_fk, id_rol_sistema_fk);


--
-- Name: usuario_sistema usuario_sistema_correo_key; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.usuario_sistema
    ADD CONSTRAINT usuario_sistema_correo_key UNIQUE (correo);


--
-- Name: usuario_sistema usuario_sistema_pkey; Type: CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.usuario_sistema
    ADD CONSTRAINT usuario_sistema_pkey PRIMARY KEY (id_usuario);


--
-- Name: evento_emergencia trg_alerta_emergencia_critica; Type: TRIGGER; Schema: public; Owner: emer_user
--

CREATE TRIGGER trg_alerta_emergencia_critica AFTER INSERT ON public.evento_emergencia FOR EACH ROW EXECUTE FUNCTION public.fn_alerta_emergencia_critica();


--
-- Name: lectura_iot trg_alerta_lectura_iot; Type: TRIGGER; Schema: public; Owner: emer_user
--

CREATE TRIGGER trg_alerta_lectura_iot AFTER INSERT ON public.lectura_iot FOR EACH ROW EXECUTE FUNCTION public.fn_alerta_lectura_iot();


--
-- Name: evento_emergencia trg_auditoria_evento_insert; Type: TRIGGER; Schema: public; Owner: emer_user
--

CREATE TRIGGER trg_auditoria_evento_insert AFTER INSERT ON public.evento_emergencia FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_evento_insert();


--
-- Name: personal_medico trg_auditoria_medico_insert; Type: TRIGGER; Schema: public; Owner: emer_user
--

CREATE TRIGGER trg_auditoria_medico_insert AFTER INSERT ON public.personal_medico FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_medico_insert();


--
-- Name: personal_medico trg_auditoria_medico_update; Type: TRIGGER; Schema: public; Owner: emer_user
--

CREATE TRIGGER trg_auditoria_medico_update AFTER UPDATE ON public.personal_medico FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_medico_update();


--
-- Name: paciente trg_auditoria_paciente_insert; Type: TRIGGER; Schema: public; Owner: emer_user
--

CREATE TRIGGER trg_auditoria_paciente_insert AFTER INSERT ON public.paciente FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_paciente_insert();


--
-- Name: ubicacion_personal trg_desactivar_ubicacion_anterior; Type: TRIGGER; Schema: public; Owner: emer_user
--

CREATE TRIGGER trg_desactivar_ubicacion_anterior AFTER INSERT ON public.ubicacion_personal FOR EACH ROW EXECUTE FUNCTION public.fn_desactivar_ubicacion_anterior();


--
-- Name: evento_emergencia trg_notificar_cierre_evento; Type: TRIGGER; Schema: public; Owner: emer_user
--

CREATE TRIGGER trg_notificar_cierre_evento AFTER UPDATE ON public.evento_emergencia FOR EACH ROW EXECUTE FUNCTION public.fn_notificar_cierre_evento();


--
-- Name: uso_medicamento_evento trg_reducir_stock_medicamento; Type: TRIGGER; Schema: public; Owner: emer_user
--

CREATE TRIGGER trg_reducir_stock_medicamento AFTER INSERT ON public.uso_medicamento_evento FOR EACH ROW EXECUTE FUNCTION public.fn_reducir_stock_medicamento();


--
-- Name: signos_vitales trg_validar_signos_vitales; Type: TRIGGER; Schema: public; Owner: emer_user
--

CREATE TRIGGER trg_validar_signos_vitales BEFORE INSERT ON public.signos_vitales FOR EACH ROW EXECUTE FUNCTION public.fn_validar_signos_vitales();


--
-- Name: alergia_paciente alergia_paciente_id_paciente_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.alergia_paciente
    ADD CONSTRAINT alergia_paciente_id_paciente_fk_fkey FOREIGN KEY (id_paciente_fk) REFERENCES public.paciente(id_paciente);


--
-- Name: alerta_iot alerta_iot_id_lectura_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.alerta_iot
    ADD CONSTRAINT alerta_iot_id_lectura_fk_fkey FOREIGN KEY (id_lectura_fk) REFERENCES public.lectura_iot(id_lectura);


--
-- Name: antecedente_medico antecedente_medico_id_paciente_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.antecedente_medico
    ADD CONSTRAINT antecedente_medico_id_paciente_fk_fkey FOREIGN KEY (id_paciente_fk) REFERENCES public.paciente(id_paciente);


--
-- Name: auditoria auditoria_id_usuario_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_id_usuario_fk_fkey FOREIGN KEY (id_usuario_fk) REFERENCES public.usuario_sistema(id_usuario);


--
-- Name: cama cama_id_estado_cama_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.cama
    ADD CONSTRAINT cama_id_estado_cama_fk_fkey FOREIGN KEY (id_estado_cama_fk) REFERENCES public.catalogo_estado_cama(id_estado_cama);


--
-- Name: cama cama_id_sala_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.cama
    ADD CONSTRAINT cama_id_sala_fk_fkey FOREIGN KEY (id_sala_fk) REFERENCES public.sala_servicio(id_sala);


--
-- Name: detalle_tratamiento_medicamento detalle_tratamiento_medicamento_id_medicamento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.detalle_tratamiento_medicamento
    ADD CONSTRAINT detalle_tratamiento_medicamento_id_medicamento_fk_fkey FOREIGN KEY (id_medicamento_fk) REFERENCES public.medicamento_inventario(id_medicamento);


--
-- Name: detalle_tratamiento_medicamento detalle_tratamiento_medicamento_id_tratamiento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.detalle_tratamiento_medicamento
    ADD CONSTRAINT detalle_tratamiento_medicamento_id_tratamiento_fk_fkey FOREIGN KEY (id_tratamiento_fk) REFERENCES public.catalogo_tratamiento(id_tratamiento);


--
-- Name: dispositivo_iot dispositivo_iot_id_hospital_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.dispositivo_iot
    ADD CONSTRAINT dispositivo_iot_id_hospital_fk_fkey FOREIGN KEY (id_hospital_fk) REFERENCES public.hospital(id_hospital);


--
-- Name: dispositivo_iot dispositivo_iot_id_sala_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.dispositivo_iot
    ADD CONSTRAINT dispositivo_iot_id_sala_fk_fkey FOREIGN KEY (id_sala_fk) REFERENCES public.sala_servicio(id_sala);


--
-- Name: evento_diagnostico evento_diagnostico_id_diagnostico_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_diagnostico
    ADD CONSTRAINT evento_diagnostico_id_diagnostico_fk_fkey FOREIGN KEY (id_diagnostico_fk) REFERENCES public.catalogo_diagnostico(id_diagnostico);


--
-- Name: evento_diagnostico evento_diagnostico_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_diagnostico
    ADD CONSTRAINT evento_diagnostico_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: evento_emergencia evento_emergencia_id_cama_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_emergencia
    ADD CONSTRAINT evento_emergencia_id_cama_fk_fkey FOREIGN KEY (id_cama_fk) REFERENCES public.cama(id_cama);


--
-- Name: evento_emergencia evento_emergencia_id_estado_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_emergencia
    ADD CONSTRAINT evento_emergencia_id_estado_evento_fk_fkey FOREIGN KEY (id_estado_evento_fk) REFERENCES public.catalogo_estado_evento(id_estado_evento);


--
-- Name: evento_emergencia evento_emergencia_id_gravedad_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_emergencia
    ADD CONSTRAINT evento_emergencia_id_gravedad_fk_fkey FOREIGN KEY (id_gravedad_fk) REFERENCES public.catalogo_nivel_gravedad(id_gravedad);


--
-- Name: evento_emergencia evento_emergencia_id_hospital_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_emergencia
    ADD CONSTRAINT evento_emergencia_id_hospital_fk_fkey FOREIGN KEY (id_hospital_fk) REFERENCES public.hospital(id_hospital);


--
-- Name: evento_emergencia evento_emergencia_id_paciente_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_emergencia
    ADD CONSTRAINT evento_emergencia_id_paciente_fk_fkey FOREIGN KEY (id_paciente_fk) REFERENCES public.paciente(id_paciente);


--
-- Name: evento_emergencia evento_emergencia_id_personal_registro_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_emergencia
    ADD CONSTRAINT evento_emergencia_id_personal_registro_fk_fkey FOREIGN KEY (id_personal_registro_fk) REFERENCES public.personal_medico(id_personal);


--
-- Name: evento_emergencia evento_emergencia_id_sala_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_emergencia
    ADD CONSTRAINT evento_emergencia_id_sala_fk_fkey FOREIGN KEY (id_sala_fk) REFERENCES public.sala_servicio(id_sala);


--
-- Name: evento_emergencia evento_emergencia_id_tipo_emergencia_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_emergencia
    ADD CONSTRAINT evento_emergencia_id_tipo_emergencia_fk_fkey FOREIGN KEY (id_tipo_emergencia_fk) REFERENCES public.catalogo_tipo_emergencia(id_tipo_emergencia);


--
-- Name: evento_tratamiento evento_tratamiento_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_tratamiento
    ADD CONSTRAINT evento_tratamiento_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: evento_tratamiento evento_tratamiento_id_tratamiento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.evento_tratamiento
    ADD CONSTRAINT evento_tratamiento_id_tratamiento_fk_fkey FOREIGN KEY (id_tratamiento_fk) REFERENCES public.catalogo_tratamiento(id_tratamiento);


--
-- Name: hospital hospital_id_municipio_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.hospital
    ADD CONSTRAINT hospital_id_municipio_fk_fkey FOREIGN KEY (id_municipio_fk) REFERENCES public.municipio(id_municipio);


--
-- Name: lectura_iot lectura_iot_id_dispositivo_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.lectura_iot
    ADD CONSTRAINT lectura_iot_id_dispositivo_fk_fkey FOREIGN KEY (id_dispositivo_fk) REFERENCES public.dispositivo_iot(id_dispositivo);


--
-- Name: lectura_iot lectura_iot_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.lectura_iot
    ADD CONSTRAINT lectura_iot_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: medicamento_inventario medicamento_inventario_id_hospital_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.medicamento_inventario
    ADD CONSTRAINT medicamento_inventario_id_hospital_fk_fkey FOREIGN KEY (id_hospital_fk) REFERENCES public.hospital(id_hospital);


--
-- Name: medico_especialidad medico_especialidad_id_especialidad_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.medico_especialidad
    ADD CONSTRAINT medico_especialidad_id_especialidad_fk_fkey FOREIGN KEY (id_especialidad_fk) REFERENCES public.catalogo_especialidad(id_especialidad);


--
-- Name: medico_especialidad medico_especialidad_id_medico_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.medico_especialidad
    ADD CONSTRAINT medico_especialidad_id_medico_fk_fkey FOREIGN KEY (id_medico_fk) REFERENCES public.personal_medico(id_personal);


--
-- Name: metrica_evento metrica_evento_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.metrica_evento
    ADD CONSTRAINT metrica_evento_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: municipio municipio_id_estado_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.municipio
    ADD CONSTRAINT municipio_id_estado_fk_fkey FOREIGN KEY (id_estado_fk) REFERENCES public.estado(id_estado);


--
-- Name: notificacion notificacion_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.notificacion
    ADD CONSTRAINT notificacion_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: notificacion notificacion_id_usuario_destino_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.notificacion
    ADD CONSTRAINT notificacion_id_usuario_destino_fk_fkey FOREIGN KEY (id_usuario_destino_fk) REFERENCES public.usuario_sistema(id_usuario);


--
-- Name: paciente paciente_id_municipio_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.paciente
    ADD CONSTRAINT paciente_id_municipio_fk_fkey FOREIGN KEY (id_municipio_fk) REFERENCES public.municipio(id_municipio);


--
-- Name: paciente paciente_id_tipo_sangre_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.paciente
    ADD CONSTRAINT paciente_id_tipo_sangre_fk_fkey FOREIGN KEY (id_tipo_sangre_fk) REFERENCES public.catalogo_tipo_sangre(id_tipo_sangre);


--
-- Name: paciente_tutor paciente_tutor_id_paciente_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.paciente_tutor
    ADD CONSTRAINT paciente_tutor_id_paciente_fk_fkey FOREIGN KEY (id_paciente_fk) REFERENCES public.paciente(id_paciente);


--
-- Name: paciente_tutor paciente_tutor_id_parentesco_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.paciente_tutor
    ADD CONSTRAINT paciente_tutor_id_parentesco_fk_fkey FOREIGN KEY (id_parentesco_fk) REFERENCES public.catalogo_parentesco(id_parentesco);


--
-- Name: paciente_tutor paciente_tutor_id_tutor_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.paciente_tutor
    ADD CONSTRAINT paciente_tutor_id_tutor_fk_fkey FOREIGN KEY (id_tutor_fk) REFERENCES public.tutor_legal(id_tutor);


--
-- Name: participacion_evento participacion_evento_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.participacion_evento
    ADD CONSTRAINT participacion_evento_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: participacion_evento participacion_evento_id_personal_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.participacion_evento
    ADD CONSTRAINT participacion_evento_id_personal_fk_fkey FOREIGN KEY (id_personal_fk) REFERENCES public.personal_medico(id_personal);


--
-- Name: participacion_evento participacion_evento_id_rol_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.participacion_evento
    ADD CONSTRAINT participacion_evento_id_rol_evento_fk_fkey FOREIGN KEY (id_rol_evento_fk) REFERENCES public.catalogo_rol_evento(id_rol_evento);


--
-- Name: personal_medico personal_medico_id_cargo_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.personal_medico
    ADD CONSTRAINT personal_medico_id_cargo_fk_fkey FOREIGN KEY (id_cargo_fk) REFERENCES public.catalogo_cargo(id_cargo);


--
-- Name: personal_medico personal_medico_id_hospital_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.personal_medico
    ADD CONSTRAINT personal_medico_id_hospital_fk_fkey FOREIGN KEY (id_hospital_fk) REFERENCES public.hospital(id_hospital);


--
-- Name: personal_medico personal_medico_id_turno_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.personal_medico
    ADD CONSTRAINT personal_medico_id_turno_fk_fkey FOREIGN KEY (id_turno_fk) REFERENCES public.catalogo_turno(id_turno);


--
-- Name: pulsera_nfc_paciente pulsera_nfc_paciente_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.pulsera_nfc_paciente
    ADD CONSTRAINT pulsera_nfc_paciente_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: pulsera_nfc_paciente pulsera_nfc_paciente_id_paciente_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.pulsera_nfc_paciente
    ADD CONSTRAINT pulsera_nfc_paciente_id_paciente_fk_fkey FOREIGN KEY (id_paciente_fk) REFERENCES public.paciente(id_paciente);


--
-- Name: reporte_estadistico reporte_estadistico_id_hospital_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.reporte_estadistico
    ADD CONSTRAINT reporte_estadistico_id_hospital_fk_fkey FOREIGN KEY (id_hospital_fk) REFERENCES public.hospital(id_hospital);


--
-- Name: resultado_clinico resultado_clinico_id_estado_egreso_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.resultado_clinico
    ADD CONSTRAINT resultado_clinico_id_estado_egreso_fk_fkey FOREIGN KEY (id_estado_egreso_fk) REFERENCES public.catalogo_estado_egreso(id_estado_egreso);


--
-- Name: resultado_clinico resultado_clinico_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.resultado_clinico
    ADD CONSTRAINT resultado_clinico_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: sala_servicio sala_servicio_id_hospital_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.sala_servicio
    ADD CONSTRAINT sala_servicio_id_hospital_fk_fkey FOREIGN KEY (id_hospital_fk) REFERENCES public.hospital(id_hospital);


--
-- Name: signos_vitales signos_vitales_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.signos_vitales
    ADD CONSTRAINT signos_vitales_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: signos_vitales signos_vitales_id_personal_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.signos_vitales
    ADD CONSTRAINT signos_vitales_id_personal_fk_fkey FOREIGN KEY (id_personal_fk) REFERENCES public.personal_medico(id_personal);


--
-- Name: tiempo_respuesta tiempo_respuesta_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.tiempo_respuesta
    ADD CONSTRAINT tiempo_respuesta_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: tiempo_respuesta tiempo_respuesta_id_momento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.tiempo_respuesta
    ADD CONSTRAINT tiempo_respuesta_id_momento_fk_fkey FOREIGN KEY (id_momento_fk) REFERENCES public.catalogo_momento_atencion(id_momento);


--
-- Name: traslado traslado_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.traslado
    ADD CONSTRAINT traslado_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: traslado traslado_id_hospital_destino_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.traslado
    ADD CONSTRAINT traslado_id_hospital_destino_fk_fkey FOREIGN KEY (id_hospital_destino_fk) REFERENCES public.hospital(id_hospital);


--
-- Name: tutor_legal tutor_legal_id_municipio_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.tutor_legal
    ADD CONSTRAINT tutor_legal_id_municipio_fk_fkey FOREIGN KEY (id_municipio_fk) REFERENCES public.municipio(id_municipio);


--
-- Name: tutor_legal tutor_legal_id_parentesco_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.tutor_legal
    ADD CONSTRAINT tutor_legal_id_parentesco_fk_fkey FOREIGN KEY (id_parentesco_fk) REFERENCES public.catalogo_parentesco(id_parentesco);


--
-- Name: tutor_legal tutor_legal_id_tipo_documento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.tutor_legal
    ADD CONSTRAINT tutor_legal_id_tipo_documento_fk_fkey FOREIGN KEY (id_tipo_documento_fk) REFERENCES public.catalogo_tipo_documento(id_tipo_documento);


--
-- Name: ubicacion_personal ubicacion_personal_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.ubicacion_personal
    ADD CONSTRAINT ubicacion_personal_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: ubicacion_personal ubicacion_personal_id_personal_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.ubicacion_personal
    ADD CONSTRAINT ubicacion_personal_id_personal_fk_fkey FOREIGN KEY (id_personal_fk) REFERENCES public.personal_medico(id_personal);


--
-- Name: ubicacion_personal ubicacion_personal_id_sala_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.ubicacion_personal
    ADD CONSTRAINT ubicacion_personal_id_sala_fk_fkey FOREIGN KEY (id_sala_fk) REFERENCES public.sala_servicio(id_sala);


--
-- Name: uso_medicamento_evento uso_medicamento_evento_id_evento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.uso_medicamento_evento
    ADD CONSTRAINT uso_medicamento_evento_id_evento_fk_fkey FOREIGN KEY (id_evento_fk) REFERENCES public.evento_emergencia(id_evento);


--
-- Name: uso_medicamento_evento uso_medicamento_evento_id_medicamento_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.uso_medicamento_evento
    ADD CONSTRAINT uso_medicamento_evento_id_medicamento_fk_fkey FOREIGN KEY (id_medicamento_fk) REFERENCES public.medicamento_inventario(id_medicamento);


--
-- Name: usuario_rol usuario_rol_id_rol_sistema_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT usuario_rol_id_rol_sistema_fk_fkey FOREIGN KEY (id_rol_sistema_fk) REFERENCES public.rol_sistema(id_rol_sistema);


--
-- Name: usuario_rol usuario_rol_id_usuario_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT usuario_rol_id_usuario_fk_fkey FOREIGN KEY (id_usuario_fk) REFERENCES public.usuario_sistema(id_usuario);


--
-- Name: usuario_sistema usuario_sistema_id_personal_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: emer_user
--

ALTER TABLE ONLY public.usuario_sistema
    ADD CONSTRAINT usuario_sistema_id_personal_fk_fkey FOREIGN KEY (id_personal_fk) REFERENCES public.personal_medico(id_personal);


--
-- PostgreSQL database dump complete
--

\unrestrict lkv3ElEg6soRu7I5IiaGgvn8CdszEJBWdGiL5ay1WcP925gC71b3qIQNxOD3t8g

