from pymongo import MongoClient
from datetime import datetime
import psycopg
from flask import Flask, render_template, request, redirect, url_for, flash, session, jsonify

app = Flask(__name__)
app.secret_key = 'emer_p_secret_key'

DB_CONFIG = {
    "host": "localhost",
    "dbname": "emergencias",
    "user": "emer_user",
    "password": "1234",
    "port": 5432
}

# ── Credenciales hardcodeadas ──
ADMIN_USER     = 'admin'
ADMIN_PASSWORD = '1234'

def get_connection():
    return psycopg.connect(**DB_CONFIG)

def get_mongo():
    client = MongoClient("mongodb://emer_user:1234@localhost:27017/sirape_analytics")
    return client["sirape_analytics"]

def login_required(f):
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated

# ==========================================
# LOGIN / LOGOUT
# ==========================================

@app.route('/login', methods=['GET', 'POST'])
def login():
    if session.get('logged_in'):
        return redirect(url_for('index'))
    error = None
    if request.method == 'POST':
        usuario  = request.form.get('usuario', '').strip()
        password = request.form.get('password', '').strip()
        if usuario == ADMIN_USER and password == ADMIN_PASSWORD:
            session['logged_in'] = True
            session['usuario']   = usuario
            return redirect(url_for('index'))
        else:
            error = 'Usuario o contraseña incorrectos.'
    return render_template('login.html', error=error)

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

# ==========================================
# INDEX / DASHBOARD
# ==========================================

@app.route('/')
@login_required
def index():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_dashboard_stats();")
            row = cur.fetchone()
            total_pacientes, total_eventos, eventos_activos, total_personal = row

            cur.execute("SELECT * FROM sp_listar_pacientes() LIMIT 5;")
            ultimos_pacientes = cur.fetchall()

            cur.execute("SELECT * FROM sp_listar_emergencias() LIMIT 5;")
            ultimas_emergencias = cur.fetchall()

            cur.execute("""
                SELECT id_notificacion, id_evento_fk, mensaje, fecha_envio
                FROM notificacion
                WHERE leida = false
                AND id_evento_fk IN (
                    SELECT id_evento FROM evento_emergencia WHERE id_gravedad_fk = 'GRV-001'
                )
                ORDER BY fecha_envio DESC LIMIT 5;
            """)
            notificaciones_criticas = cur.fetchall()

    return render_template('index.html',
                           total_pacientes=total_pacientes,
                           total_eventos=total_eventos,
                           eventos_activos=eventos_activos,
                           total_personal=total_personal,
                           ultimos_pacientes=ultimos_pacientes,
                           ultimas_emergencias=ultimas_emergencias,
                           notificaciones_criticas=notificaciones_criticas)
# ==========================================
# EMERGENCIAS - MOSTRAR
# ==========================================

@app.route('/emergencias')
@login_required
def emergencias():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_listar_emergencias();")
            lista_emergencias = cur.fetchall()
            cur.execute("SELECT * FROM sp_catalogo_tipos_emergencia();")
            tipos = cur.fetchall()
            cur.execute("SELECT * FROM sp_catalogo_gravedades();")
            gravedades = cur.fetchall()
            cur.execute("SELECT * FROM sp_catalogo_hospitales();")
            hospitales = cur.fetchall()
    return render_template('emergencias.html',
                           emergencias=lista_emergencias,
                           tipos=tipos,
                           gravedades=gravedades,
                           hospitales=hospitales)

# ==========================================
# EMERGENCIAS - REGISTRAR (GET)
# ==========================================

@app.route('/registrar_emergencia', methods=['GET'])
@login_required
def registrar_emergencia():
    # Parámetros opcionales que puede mandar un beacon via URL
    beacon_id       = request.args.get('beacon')    # Ej: DIS-003
    beacon_hospital = request.args.get('hospital')  # Ej: HSP-001
    beacon_sala     = request.args.get('sala')       # Ej: SAL-001
    desde_beacon    = beacon_id is not None

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_catalogo_pacientes();")
            pacientes = cur.fetchall()
            cur.execute("SELECT * FROM sp_catalogo_tipos_emergencia();")
            tipos = cur.fetchall()
            cur.execute("SELECT * FROM sp_catalogo_gravedades();")
            gravedades = cur.fetchall()
            cur.execute("SELECT * FROM sp_catalogo_hospitales();")
            hospitales = cur.fetchall()
            cur.execute("SELECT * FROM sp_catalogo_salas();")
            salas = cur.fetchall()
            cur.execute("SELECT * FROM sp_catalogo_personal_activo();")
            personal = cur.fetchall()

            # Si viene del beacon, obtener nombre del dispositivo y sala
            beacon_nombre      = None
            beacon_sala_nombre = None
            if desde_beacon:
                cur.execute(
                    "SELECT nombre FROM dispositivo_iot WHERE id_dispositivo = %s;",
                    (beacon_id,)
                )
                row = cur.fetchone()
                beacon_nombre = row[0] if row else beacon_id

                if beacon_sala:
                    cur.execute(
                        "SELECT nombre_sala FROM sala_servicio WHERE id_sala = %s;",
                        (beacon_sala,)
                    )
                    row2 = cur.fetchone()
                    beacon_sala_nombre = row2[0] if row2 else beacon_sala

    return render_template('registrar_emergencias.html',
                           pacientes=pacientes,
                           tipos=tipos,
                           gravedades=gravedades,
                           hospitales=hospitales,
                           salas=salas,
                           personal=personal,
                           desde_beacon=desde_beacon,
                           beacon_id=beacon_id,
                           beacon_hospital=beacon_hospital,
                           beacon_sala=beacon_sala,
                           beacon_nombre=beacon_nombre,
                           beacon_sala_nombre=beacon_sala_nombre)

# ==========================================
# EMERGENCIAS - INSERTAR (POST)
# ==========================================

@app.route('/emergencias/insertar', methods=['POST'])
@login_required
def insertar_emergencia():
    id_evento     = request.form.get('id_evento', '').strip()
    id_paciente   = request.form.get('id_paciente')
    id_tipo       = request.form.get('id_tipo_emergencia')
    id_gravedad   = request.form.get('id_gravedad')
    id_hospital   = request.form.get('id_hospital')
    id_sala       = request.form.get('id_sala') or None
    id_personal   = request.form.get('id_personal_registro') or None
    observaciones = request.form.get('observaciones', '').strip() or None

    with get_connection() as conn:
        with conn.cursor() as cur:
            try:
                cur.execute(
                    "CALL sp_insertar_emergencia(%s, %s, %s, %s, %s, %s, %s, %s);",
                    (id_evento, id_paciente, id_tipo, id_gravedad,
                     id_hospital, id_sala, observaciones, id_personal)
                )
                conn.commit()
                flash('Emergencia registrada correctamente.', 'exito')
            except Exception as e:
                conn.rollback()
                flash(f'Error al registrar la emergencia: {e}', 'error')

    return redirect(url_for('emergencias'))

# ==========================================
# MÉDICOS
# ==========================================

@app.route("/medicos")
@login_required
def obtener_medicos():
    conn = None
    cur  = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur  = conn.cursor(row_factory=psycopg.rows.dict_row)
        cur.execute("SELECT * FROM sp_obtener_medicos();")
        medicos = cur.fetchall()
        cur.execute("SELECT * FROM sp_obtener_cargos();")
        cargos = cur.fetchall()
        cur.execute("SELECT * FROM sp_obtener_turnos();")
        turnos = cur.fetchall()
        cur.execute("SELECT * FROM sp_obtener_especialidades();")
        especialidades = cur.fetchall()
    except Exception as e:
        flash(f"Error al obtener médicos: {e}", "error")
        medicos, cargos, turnos, especialidades = [], [], [], []
    finally:
        if cur: cur.close()
    return render_template("medicos.html", medicos=medicos,
                           cargos=cargos, turnos=turnos, especialidades=especialidades)


@app.route("/registrarMedico", methods=["GET"])
@login_required
def registrar_medico():
    conn = None
    cur  = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur  = conn.cursor(row_factory=psycopg.rows.dict_row)
        cur.execute("SELECT * FROM sp_obtener_cargos();")
        cargos = cur.fetchall()
        cur.execute("SELECT * FROM sp_obtener_turnos();")
        turnos = cur.fetchall()
        cur.execute("SELECT * FROM sp_obtener_especialidades();")
        especialidades = cur.fetchall()
    except Exception as e:
        flash(f"Error al cargar catálogos: {e}", "error")
        cargos, turnos, especialidades = [], [], []
    finally:
        if cur: cur.close()
    return render_template("registrar_medico.html", cargos=cargos,
                           turnos=turnos, especialidades=especialidades)


@app.route("/medicos/insertar", methods=["POST"])
@login_required
def insertar_medico():
    conn = None
    cur  = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur  = conn.cursor(row_factory=psycopg.rows.dict_row)

        id_personal      = request.form.get("id_personal", "").strip()
        nombre           = request.form.get("nombre", "").strip()
        apellido_paterno = request.form.get("apellido_paterno", "").strip()
        apellido_materno = request.form.get("apellido_materno", "").strip()
        cedula           = request.form.get("cedula", "").strip()
        rfc              = request.form.get("rfc", "").strip()
        curp             = request.form.get("curp", "").strip()
        id_cargo         = request.form.get("id_cargo", "").strip()
        id_turno         = request.form.get("id_turno", "").strip()
        telefono         = request.form.get("telefono", "").strip()
        correo           = request.form.get("correo", "").strip()
        especialidades   = request.form.getlist("especialidades")

        cur.execute("""
            CALL sp_insertar_medico(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,0,'');
        """, (id_personal, nombre, apellido_paterno, apellido_materno,
              cedula, rfc, curp, id_cargo, id_turno, telefono, correo))

        for esp in especialidades:
            cur.execute("""
                INSERT INTO Medico_Especialidad (id_medico_FK, id_especialidad_FK)
                VALUES (%s, %s) ON CONFLICT DO NOTHING;
            """, (id_personal, esp))

        conn.commit()
        flash("Médico registrado correctamente.", "exito")

    except Exception as e:
        if conn: conn.rollback()
        flash(f"Error al insertar médico: {e}", "error")
    finally:
        if cur: cur.close()

    return redirect(url_for("obtener_medicos"))


@app.route("/medicos/datos/<id_personal>")
@login_required
def datos_medico(id_personal):
    conn = None
    cur  = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur  = conn.cursor(row_factory=psycopg.rows.dict_row)
        cur.execute("SELECT * FROM sp_obtener_medico_por_id(%s);", (id_personal,))
        medico = cur.fetchone()
        cur.execute("""
            SELECT id_especialidad_FK FROM Medico_Especialidad WHERE id_medico_FK = %s;
        """, (id_personal,))
        especialidades = [row["id_especialidad_fk"] for row in cur.fetchall()]
        if medico:
            medico["especialidades"] = especialidades
            return jsonify(dict(medico))
        return jsonify({"error": "No encontrado"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if cur: cur.close()


@app.route("/medicos/editar", methods=["POST"])
@login_required
def editar_medico():
    conn = None
    cur  = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur  = conn.cursor(row_factory=psycopg.rows.dict_row)

        id_personal      = request.form.get("id_personal", "").strip()
        nombre           = request.form.get("nombre", "").strip()
        apellido_paterno = request.form.get("apellido_paterno", "").strip()
        apellido_materno = request.form.get("apellido_materno", "").strip()
        cedula           = request.form.get("cedula", "").strip()
        telefono         = request.form.get("telefono", "").strip()
        correo           = request.form.get("correo", "").strip()
        id_cargo         = request.form.get("id_cargo", "").strip()
        id_turno         = request.form.get("id_turno", "").strip()
        especialidades   = request.form.getlist("especialidades")

        cur.execute("""
            CALL sp_editar_medico(%s,%s,%s,%s,%s,%s,%s,%s,%s,0,'');
        """, (id_personal, nombre, apellido_paterno, apellido_materno,
              cedula, telefono, correo, id_cargo, id_turno))

        cur.execute("DELETE FROM Medico_Especialidad WHERE id_medico_FK = %s;", (id_personal,))
        for esp in especialidades:
            cur.execute("""
                INSERT INTO Medico_Especialidad (id_medico_FK, id_especialidad_FK)
                VALUES (%s, %s) ON CONFLICT DO NOTHING;
            """, (id_personal, esp))

        conn.commit()
        flash("Médico actualizado correctamente.", "exito")

    except Exception as e:
        if conn: conn.rollback()
        flash(f"Error al editar médico: {e}", "error")
    finally:
        if cur: cur.close()

    return redirect(url_for("obtener_medicos"))


@app.route("/medicos/estado", methods=["POST"])
@login_required
def cambiar_estado_medico():
    conn = None
    cur  = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur  = conn.cursor(row_factory=psycopg.rows.dict_row)
        id_personal  = request.form.get("id_personal", "").strip()
        nuevo_estado = request.form.get("estado", "").strip()
        cur.execute("CALL sp_cambiar_estado_medico(%s,%s,0,'');", (id_personal, nuevo_estado))
        conn.commit()
        flash(f"Estado del médico actualizado a '{nuevo_estado}'.", "exito")
    except Exception as e:
        if conn: conn.rollback()
        flash(f"Error: {e}", "error")
    finally:
        if cur: cur.close()
    return redirect(url_for("obtener_medicos"))

# ==========================================
# PACIENTES
# ==========================================

@app.route('/pacientes')
@login_required
def pacientes():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_listar_pacientes();")
            lista_pacientes = cur.fetchall()
            cur.execute("SELECT * FROM sp_catalogo_tipo_sangre();")
            tipos_sangre = cur.fetchall()
            cur.execute("SELECT * FROM sp_catalogo_municipios();")
            municipios = cur.fetchall()
    return render_template('pacientes.html', pacientes=lista_pacientes,
                           tipos_sangre=tipos_sangre, municipios=municipios)

@app.route('/pacientes/insertar', methods=['POST'])
@login_required
def insertar_paciente():
    id_paciente      = request.form.get('id_paciente', '').strip()
    nombre           = request.form.get('nombre', '').strip()
    apellido_paterno = request.form.get('apellido_paterno', '').strip()
    apellido_materno = request.form.get('apellido_materno', '').strip() or None
    fecha_nacimiento = request.form.get('fecha_nacimiento', '').strip()
    sexo             = request.form.get('sexo', '').strip()
    curp             = request.form.get('curp', '').strip() or None
    id_tipo_sangre   = request.form.get('id_tipo_sangre', '').strip() or None
    peso_kg          = request.form.get('peso_kg', '').strip() or None
    talla_cm         = request.form.get('talla_cm', '').strip() or None
    id_municipio     = request.form.get('id_municipio', '').strip() or None

    with get_connection() as conn:
        with conn.cursor() as cur:
            try:
                cur.execute(
                    "CALL sp_insertar_paciente(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);",
                    (id_paciente, nombre, apellido_paterno, apellido_materno,
                     fecha_nacimiento, sexo, curp, id_tipo_sangre,
                     peso_kg, talla_cm, id_municipio)
                )
                conn.commit()
                flash('Paciente registrado correctamente.', 'exito')
            except Exception as e:
                conn.rollback()
                flash(f'Error al registrar paciente: {e}', 'error')

    return redirect(url_for('pacientes'))

@app.route('/pacientes/<id_paciente>')
@login_required
def detalle_paciente(id_paciente):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_detalle_paciente(%s);", (id_paciente,))
            paciente = cur.fetchone()
            cur.execute("SELECT * FROM sp_tutores_paciente(%s);", (id_paciente,))
            tutores = cur.fetchall()
            cur.execute("SELECT * FROM sp_eventos_paciente(%s);", (id_paciente,))
            eventos = cur.fetchall()
    return render_template('pacientes.html', paciente=paciente, tutores=tutores,
                           eventos=eventos, detalle=True)

@app.route('/pacientes/cerrar', methods=['POST'])
@login_required
def cerrar_caso_paciente():
    id_paciente = request.form.get('id_paciente', '').strip()
    with get_connection() as conn:
        with conn.cursor() as cur:
            try:
                cur.execute(
                    "CALL sp_cambiar_estado_paciente(%s, 'Cerrado', 0, '');",
                    (id_paciente,)
                )
                conn.commit()
                flash(f'Caso {id_paciente} cerrado correctamente.', 'exito')
            except Exception as e:
                conn.rollback()
                flash(f'Error al cerrar caso: {e}', 'error')
    return redirect(url_for('pacientes'))

# ==========================================
# EVENTOS DE EMERGENCIA
# ==========================================

@app.route('/eventos')
@login_required
def eventos():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_listar_eventos();")
            lista_eventos = cur.fetchall()
    return render_template('eventos.html', eventos=lista_eventos)

@app.route('/eventos/<id_evento>')
@login_required
def detalle_evento(id_evento):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_detalle_evento(%s);", (id_evento,))
            evento = cur.fetchone()
            cur.execute("SELECT * FROM sp_participaciones_evento(%s);", (id_evento,))
            participaciones = cur.fetchall()
            cur.execute("SELECT * FROM sp_signos_vitales_evento(%s);", (id_evento,))
            signos = cur.fetchall()
            cur.execute("SELECT * FROM sp_tiempos_respuesta_evento(%s);", (id_evento,))
            tiempos = cur.fetchall()
    return render_template('eventos.html', evento=evento, participaciones=participaciones,
                           signos=signos, tiempos=tiempos, detalle=True)

# ==========================================
# PERSONAL MÉDICO
# ==========================================

@app.route('/personal')
@login_required
def personal():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_listar_personal();")
            lista_personal = cur.fetchall()
    return render_template('personal.html', personal=lista_personal)

@app.route('/personal/<id_personal>')
@login_required
def detalle_personal(id_personal):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_detalle_personal(%s);", (id_personal,))
            medico = cur.fetchone()
            cur.execute("SELECT * FROM sp_especialidades_personal(%s);", (id_personal,))
            especialidades = cur.fetchall()
            cur.execute("SELECT * FROM sp_participaciones_personal(%s);", (id_personal,))
            participaciones = cur.fetchall()
    return render_template('personal.html', medico=medico, especialidades=especialidades,
                           participaciones=participaciones, detalle=True)

# ==========================================
# USUARIOS DEL SISTEMA
# ==========================================

@app.route('/usuarios')
@login_required
def usuarios():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_listar_usuarios();")
            lista_usuarios = cur.fetchall()
    return render_template('usuarios.html', usuarios=lista_usuarios)

# ==========================================
# IoT
# ==========================================

@app.route('/iot')
@login_required
def iot():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_listar_dispositivos_iot();")
            dispositivos = cur.fetchall()

            cur.execute("SELECT * FROM sp_lecturas_recientes_iot();")
            lecturas = cur.fetchall()

            cur.execute("SELECT * FROM sp_alertas_iot();")
            alertas_iot = cur.fetchall()

            cur.execute("""
                SELECT 
                    'emergencia' as tipo,
                    n.id_notificacion::text as id,
                    n.id_evento_fk as referencia,
                    n.mensaje,
                    n.fecha_envio as fecha,
                    n.leida as atendida,
                    cng.nivel as gravedad
                FROM notificacion n
                LEFT JOIN evento_emergencia ee ON n.id_evento_fk = ee.id_evento
                LEFT JOIN catalogo_nivel_gravedad cng ON ee.id_gravedad_fk = cng.id_gravedad
                UNION ALL
                SELECT
                    'iot' as tipo,
                    a.id_alerta::text as id,
                    a.id_lectura_fk::text as referencia,
                    a.mensaje,
                    l.timestamp as fecha,
                    a.atendida,
                    NULL as gravedad
                FROM alerta_iot a
                JOIN lectura_iot l ON a.id_lectura_fk = l.id_lectura
                ORDER BY fecha DESC;
            """)
            todas_alertas = cur.fetchall()

    total_dispositivos   = len(dispositivos)
    dispositivos_activos = sum(1 for d in dispositivos if d[5] == 'Activo')
    alertas_pendientes   = sum(1 for a in todas_alertas if not a[5])
    total_lecturas       = len(lecturas)

    return render_template('iot.html',
                           dispositivos=dispositivos,
                           lecturas=lecturas,
                           alertas_iot=alertas_iot,
                           todas_alertas=todas_alertas,
                           total_dispositivos=total_dispositivos,
                           dispositivos_activos=dispositivos_activos,
                           alertas_pendientes=alertas_pendientes,
                           total_lecturas=total_lecturas)

@app.route('/medico/ubicacion', methods=['POST'])
@login_required
def registrar_ubicacion_medico():
    """
    Recibe: id_personal, id_evento, id_sala
    Llama al stored procedure sp_registrar_ubicacion_medico
    que guarda la ubicación y genera una lectura en lectura_iot
    vinculada al beacon DIS-003.
    """
    id_personal = request.form.get('id_personal')
    id_evento   = request.form.get('id_evento')
    id_sala     = request.form.get('id_sala')

    with get_connection() as conn:
        with conn.cursor() as cur:
            try:
                cur.execute(
                    "CALL sp_registrar_ubicacion_medico(%s, %s, %s);",
                    (id_personal, id_evento, id_sala)
                )
                cur.execute("UPDATE notificacion SET leida = true WHERE id_evento_fk = %s;", (id_evento,))
                conn.commit()
                return jsonify({'ok': True, 'mensaje': 'Ubicación registrada correctamente'}), 200
            except Exception as e:
                conn.rollback()
                return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/medico/ubicaciones')
@login_required
def ver_ubicaciones():
    """
    Devuelve JSON con todos los médicos que están
    actualmente atendiendo pacientes y en qué sala están.
    Se consulta desde la vista v_ubicacion_activa_personal.
    """
    with get_connection() as conn:
        with conn.cursor(row_factory=psycopg.rows.dict_row) as cur:
            try:
                cur.execute("SELECT * FROM v_ubicacion_activa_personal;")
                ubicaciones = cur.fetchall()
                return jsonify([dict(u) for u in ubicaciones]), 200
            except Exception as e:
                return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/medico/activos')
@login_required
def medico_activos():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_catalogo_personal_activo();")
            personal = cur.fetchall()
    return jsonify(personal)

# ==========================================
# REPORTES / ANÁLISIS
# ==========================================

@app.route('/reportes')
@login_required
def reportes():
    return render_template('reportes.html')

# ==========================================
# ANALYTICS - KPI endpoints para Highcharts
# ==========================================

@app.route('/api/kpi/emergencias_por_tipo')
@login_required
def kpi_emergencias_tipo():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT cte.nombre AS tipo, COUNT(*) AS total
                FROM evento_emergencia ee
                JOIN Catalogo_Tipo_Emergencia cte
                  ON ee.id_tipo_emergencia_FK = cte.id_tipo_emergencia
                GROUP BY cte.nombre
                ORDER BY total DESC;
            """)
            rows = cur.fetchall()

    data = [{"tipo": r[0], "total": int(r[1])} for r in rows]

    db = get_mongo()
    db.kpi_emergencias_tipo.insert_one({"fecha": datetime.utcnow(), "datos": data})

    return jsonify(data)


@app.route('/api/kpi/emergencias_por_gravedad')
@login_required
def kpi_emergencias_gravedad():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT cng.nivel AS gravedad, COUNT(*) AS total
                FROM evento_emergencia ee
                JOIN catalogo_nivel_gravedad cng
                  ON ee.id_gravedad_fk = cng.id_gravedad
                GROUP BY cng.nivel
                ORDER BY total DESC;
            """)
            rows = cur.fetchall()

    data = [{"gravedad": r[0], "total": int(r[1])} for r in rows]

    db = get_mongo()
    db.kpi_emergencias_gravedad.insert_one({"fecha": datetime.utcnow(), "datos": data})

    return jsonify(data)


@app.route('/api/kpi/pacientes_por_edad')
@login_required
def kpi_pacientes_edad():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                  CASE
                    WHEN EXTRACT(YEAR FROM AGE(fecha_nacimiento)) BETWEEN 0  AND 2  THEN '0–2 años'
                    WHEN EXTRACT(YEAR FROM AGE(fecha_nacimiento)) BETWEEN 3  AND 6  THEN '3–6 años'
                    WHEN EXTRACT(YEAR FROM AGE(fecha_nacimiento)) BETWEEN 7  AND 12 THEN '7–12 años'
                    WHEN EXTRACT(YEAR FROM AGE(fecha_nacimiento)) BETWEEN 13 AND 17 THEN '13–17 años'
                    ELSE 'Otro'
                  END AS rango,
                  COUNT(*) AS total
                FROM Paciente
                WHERE fecha_nacimiento IS NOT NULL
                GROUP BY rango
                ORDER BY MIN(EXTRACT(YEAR FROM AGE(fecha_nacimiento)));
            """)
            rows = cur.fetchall()

    data = [{"rango": r[0], "total": int(r[1])} for r in rows]

    db = get_mongo()
    db.kpi_pacientes_edad.insert_one({"fecha": datetime.utcnow(), "datos": data})

    return jsonify(data)


@app.route('/api/kpi/medicos_top')
@login_required
def kpi_medicos_top():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                  pm.nombre || ' ' || pm.apellido_paterno AS medico,
                  COUNT(ee.id_evento) AS total
                FROM Personal_Medico pm
                JOIN Evento_Emergencia ee
                  ON ee.id_personal_registro_FK = pm.id_personal
                GROUP BY pm.id_personal, medico
                ORDER BY total DESC
                LIMIT 8;
            """)
            rows = cur.fetchall()

    data = [{"medico": r[0], "total": int(r[1])} for r in rows]

    db = get_mongo()
    db.kpi_medicos_top.insert_one({"fecha": datetime.utcnow(), "datos": data})

    return jsonify(data)


@app.route('/api/kpi/urgencias_por_turno')
@login_required
def kpi_urgencias_turno():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                  ct.nombre AS turno,
                  COUNT(ee.id_evento) AS total
                FROM evento_emergencia ee
                JOIN Personal_Medico pm
                  ON ee.id_personal_registro_FK = pm.id_personal
                JOIN Catalogo_Turno ct
                  ON pm.id_turno_FK = ct.id_turno
                GROUP BY ct.nombre
                ORDER BY total DESC;
            """)
            rows = cur.fetchall()

    data = [{"turno": r[0], "total": int(r[1])} for r in rows]

    db = get_mongo()
    db.kpi_urgencias_turno.insert_one({"fecha": datetime.utcnow(), "datos": data})

    return jsonify(data)

@app.route('/emergencias/atender', methods=['POST'])
@login_required
def atender_emergencia():
    id_evento = request.form.get('id_evento')
    with get_connection() as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("""
                    UPDATE evento_emergencia 
                    SET id_estado_evento_fk = 'EST-002'
                    WHERE id_evento = %s;
                """, (id_evento,))
                cur.execute("UPDATE notificacion SET leida = true WHERE id_evento_fk = %s;", (id_evento,))
                conn.commit()
                return jsonify({'ok': True}), 200
            except Exception as e:
                conn.rollback()
                return jsonify({'ok': False, 'error': str(e)}), 500


# ==========================================
# MAIN
# ==========================================

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
