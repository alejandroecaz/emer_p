from pymongo import MongoClient
from datetime import datetime
from functools import wraps
import psycopg
import psycopg.rows
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

def get_connection():
    return psycopg.connect(**DB_CONFIG)

def get_mongo():
    client = MongoClient("mongodb://emer_user:1234@localhost:27017/sirape_analytics")
    return client["sirape_analytics"]


# ==========================================
# DECORADORES DE ACCESO
# ==========================================

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated

def admin_required(f):
    """Solo admins. Si no, redirige al dashboard del usuario."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect(url_for('login'))
        if session.get('rol') != 'Administrador':
            flash('Acceso restringido a administradores.', 'error')
            return redirect(url_for('dashboard'))
        return f(*args, **kwargs)
    return decorated

def medico_enfermero_required(f):
    """Médicos y enfermeros (no admin)."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect(url_for('login'))
        if session.get('rol') not in ('Médico', 'Enfermero'):
            flash('Acceso restringido a personal médico.', 'error')
            return redirect(url_for('index'))
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

        with get_connection() as conn:
            with conn.cursor(row_factory=psycopg.rows.dict_row) as cur:
                # Buscar por correo O por id_usuario (para que "admin" también funcione)
                cur.execute("""
                    SELECT us.id_usuario, us.correo, us.contrasena,
                           us.id_personal_fk, us.estado_cuenta,
                           rs.nombre_rol
                    FROM usuario_sistema us
                    JOIN usuario_rol ur ON us.id_usuario = ur.id_usuario_fk
                    JOIN rol_sistema rs ON ur.id_rol_sistema_fk = rs.id_rol_sistema
                    WHERE (us.correo = %s OR us.id_usuario = %s)
                      AND us.estado_cuenta = 'Activo'
                    LIMIT 1;
                """, (usuario, usuario))
                user = cur.fetchone()

        if user and user['contrasena'] == password:
            session['logged_in']   = True
            session['id_usuario']  = user['id_usuario']
            session['usuario']     = user['correo']
            session['rol']         = user['nombre_rol']       # 'Administrador', 'Médico', 'Enfermero'
            session['id_personal'] = user['id_personal_fk']  # None para admin puro

            # Actualizar ultimo_login
            with get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "UPDATE usuario_sistema SET ultimo_login = NOW() WHERE id_usuario = %s;",
                        (user['id_usuario'],)
                    )
                    conn.commit()

            # Redirigir según rol
            if session['rol'] == 'Administrador':
                return redirect(url_for('index'))
            else:
                return redirect(url_for('dashboard'))
        else:
            error = 'Usuario o contraseña incorrectos.'

    return render_template('login.html', error=error)


@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))


# ==========================================
# DASHBOARD MÉDICO / ENFERMERO
# ==========================================

@app.route('/dashboard')
@medico_enfermero_required
def dashboard():
    """Vista principal para médicos y enfermeros."""
    id_personal = session.get('id_personal')
    rol         = session.get('rol')

    with get_connection() as conn:
        with conn.cursor() as cur:

            # Emergencias asignadas a este personal (vía participacion_evento)
            cur.execute("""
                SELECT ee.id_evento, ee.id_paciente_fk,
                       p.nombre || ' ' || p.apellido_paterno AS paciente,
                       te.nombre AS tipo,
                       cng.nivel AS gravedad,
                       cee.nombre AS estado,
                       ee.fecha_hora_ingreso,
                       ss.nombre_sala AS sala
                FROM evento_emergencia ee
                JOIN participacion_evento pe ON ee.id_evento = pe.id_evento_fk
                JOIN paciente p             ON ee.id_paciente_fk = p.id_paciente
                JOIN catalogo_tipo_emergencia te ON ee.id_tipo_emergencia_fk = te.id_tipo_emergencia
                JOIN catalogo_nivel_gravedad cng ON ee.id_gravedad_fk = cng.id_gravedad
                JOIN catalogo_estado_evento cee  ON ee.id_estado_evento_fk = cee.id_estado_evento
                LEFT JOIN sala_servicio ss        ON ee.id_sala_fk = ss.id_sala
                WHERE pe.id_personal_fk = %s
                  AND ee.id_estado_evento_fk != 'EST-003'
                ORDER BY ee.fecha_hora_ingreso DESC;
            """, (id_personal,))
            mis_emergencias = cur.fetchall()

            # Emergencias disponibles (sin personal asignado o solo con enfermero)
            cur.execute("""
                SELECT ee.id_evento,
                       p.nombre || ' ' || p.apellido_paterno AS paciente,
                       te.nombre AS tipo,
                       cng.nivel AS gravedad,
                       cee.nombre AS estado,
                       ee.fecha_hora_ingreso
                FROM evento_emergencia ee
                JOIN paciente p                   ON ee.id_paciente_fk = p.id_paciente
                JOIN catalogo_tipo_emergencia te  ON ee.id_tipo_emergencia_fk = te.id_tipo_emergencia
                JOIN catalogo_nivel_gravedad cng  ON ee.id_gravedad_fk = cng.id_gravedad
                JOIN catalogo_estado_evento cee   ON ee.id_estado_evento_fk = cee.id_estado_evento
                WHERE ee.id_estado_evento_fk = 'EST-001'
                  AND ee.id_evento NOT IN (
                      SELECT id_evento_fk FROM participacion_evento WHERE id_personal_fk = %s
                  )
                ORDER BY ee.fecha_hora_ingreso DESC
                LIMIT 20;
            """, (id_personal,))
            emergencias_disponibles = cur.fetchall()

    return render_template('dashboard.html',
                           mis_emergencias=mis_emergencias,
                           emergencias_disponibles=emergencias_disponibles,
                           rol=rol,
                           id_personal=id_personal)


# ==========================================
# TOMAR EMERGENCIA (médico / enfermero)
# ==========================================

@app.route('/emergencias/tomar', methods=['POST'])
@medico_enfermero_required
def tomar_emergencia():
    """El médico o enfermero toma una emergencia disponible."""
    id_evento   = request.form.get('id_evento')
    id_personal = session.get('id_personal')
    rol         = session.get('rol')

    # Mapeo de rol a rol_evento
    rol_evento_map = {
        'Médico':    'ROL-001',   # Médico Responsable
        'Enfermero': 'ROL-003',   # Enfermero Asignado
    }
    id_rol_evento = rol_evento_map.get(rol, 'ROL-001')

    with get_connection() as conn:
        with conn.cursor() as cur:
            try:
                # Insertar participación
                cur.execute("""
                    INSERT INTO participacion_evento
                        (id_evento_fk, id_personal_fk, id_rol_evento_fk, hora_inicio)
                    VALUES (%s, %s, %s, NOW()::time)
                    ON CONFLICT DO NOTHING;
                """, (id_evento, id_personal, id_rol_evento))

                # Marcar notificaciones como leídas
                cur.execute(
                    "UPDATE notificacion SET leida = true WHERE id_evento_fk = %s;",
                    (id_evento,)
                )
                conn.commit()
                flash(f'Emergencia {id_evento} tomada correctamente.', 'exito')
            except Exception as e:
                conn.rollback()
                flash(f'Error al tomar la emergencia: {e}', 'error')

    return redirect(url_for('dashboard'))


# ==========================================
# INDEX / DASHBOARD ADMIN
# ==========================================

@app.route('/')
@login_required
def index():
    # Si no es admin, redirigir a su dashboard
    if session.get('rol') != 'Administrador':
        return redirect(url_for('dashboard'))

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
@admin_required
def registrar_emergencia():
    beacon_id       = request.args.get('beacon')
    beacon_hospital = request.args.get('hospital')
    beacon_sala     = request.args.get('sala')
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
@admin_required
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
# EMERGENCIAS - ASIGNAR PERSONAL (admin)
# ==========================================

@app.route('/emergencias/asignar', methods=['POST'])
@admin_required
def asignar_personal_emergencia():
    """Admin asigna un médico o enfermero a una emergencia."""
    id_evento   = request.form.get('id_evento')
    id_personal = request.form.get('id_personal')
    id_rol_evento = request.form.get('id_rol_evento', 'ROL-001')

    with get_connection() as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("""
                    INSERT INTO participacion_evento
                        (id_evento_fk, id_personal_fk, id_rol_evento_fk, hora_inicio)
                    VALUES (%s, %s, %s, NOW()::time)
                    ON CONFLICT DO NOTHING;
                """, (id_evento, id_personal, id_rol_evento))

                conn.commit()
                return jsonify({'ok': True, 'mensaje': 'Personal asignado correctamente'}), 200
            except Exception as e:
                conn.rollback()
                return jsonify({'ok': False, 'error': str(e)}), 500


# ==========================================
# MÉDICOS
# ==========================================

@app.route("/medicos")
@admin_required
def obtener_medicos():
    conn = None
    cur  = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur  = conn.cursor(row_factory=psycopg.rows.dict_row)
        cur.execute("SELECT * FROM sp_obtener_medicos();")
        medicos = cur.fetchall()
        # Solo cargos médico y enfermero (CAR-001, CAR-002, CAR-003)
        cur.execute("""
            SELECT id_cargo, nombre FROM catalogo_cargo
            WHERE id_cargo IN ('CAR-001', 'CAR-002', 'CAR-003')
            ORDER BY nombre;
        """)
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
@admin_required
def registrar_medico():
    conn = None
    cur  = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur  = conn.cursor(row_factory=psycopg.rows.dict_row)
        # Solo cargos médico y enfermero
        cur.execute("""
            SELECT id_cargo, nombre FROM catalogo_cargo
            WHERE id_cargo IN ('CAR-001', 'CAR-002', 'CAR-003')
            ORDER BY nombre;
        """)
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
@admin_required
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
@admin_required
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
@admin_required
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
@admin_required
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
@admin_required
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
@admin_required
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
# PERSONAL MÉDICO
# ==========================================

@app.route('/personal')
@admin_required
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
@admin_required
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
            cur.execute("SELECT * FROM sp_catalogo_personal_activo_con_rol();")
            personal = cur.fetchall()
    return jsonify([{"id": p[0], "nombre": p[1], "cargo": p[2]} for p in personal])


# ==========================================
# REPORTES
# ==========================================

@app.route('/reportes')
@admin_required
def reportes():
    return render_template('reportes.html')


# ==========================================
# ANALYTICS - KPI endpoints
# ==========================================

@app.route('/api/kpi/emergencias_por_tipo')
@login_required
def kpi_emergencias_tipo():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT tipo_emergencia AS tipo, total, porcentaje FROM v_kpi_emergencias_por_tipo;")
            rows = cur.fetchall()
    data = [{"tipo": r[0], "total": int(r[1]), "porcentaje": float(r[2])} for r in rows]
    db = get_mongo()
    db.kpi_emergencias_tipo.insert_one({"fecha": datetime.utcnow(), "datos": data})
    return jsonify(data)


@app.route('/api/kpi/emergencias_por_gravedad')
@login_required
def kpi_emergencias_gravedad():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT gravedad, total, porcentaje FROM v_kpi_emergencias_por_gravedad;")
            rows = cur.fetchall()
    data = [{"gravedad": r[0], "total": int(r[1]), "porcentaje": float(r[2])} for r in rows]
    db = get_mongo()
    db.kpi_emergencias_gravedad.insert_one({"fecha": datetime.utcnow(), "datos": data})
    return jsonify(data)


@app.route('/api/kpi/pacientes_por_edad')
@login_required
def kpi_pacientes_edad():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT rango_edad AS rango, total_pacientes AS total FROM v_kpi_pacientes_por_edad;")
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
            cur.execute("SELECT nombre_completo AS medico, total_eventos_atendidos AS total FROM v_kpi_medicos_top LIMIT 8;")
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
            cur.execute("SELECT turno, total_emergencias AS total FROM v_kpi_urgencias_por_turno;")
            rows = cur.fetchall()
    data = [{"turno": r[0], "total": int(r[1])} for r in rows]
    db = get_mongo()
    db.kpi_urgencias_turno.insert_one({"fecha": datetime.utcnow(), "datos": data})
    return jsonify(data)


@app.route('/api/kpi/mis_emergencias')
@medico_enfermero_required
def kpi_mis_emergencias():
    """KPI personal del médico/enfermero logueado."""
    id_personal = session.get('id_personal')
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_dashboard_medico(%s);", (id_personal,))
            stats = cur.fetchone()

            cur.execute("SELECT * FROM sp_emergencias_por_mes_medico(%s);", (id_personal,))
            por_mes = [{"mes": r[0], "total": int(r[1])} for r in cur.fetchall()]

            cur.execute("SELECT * FROM sp_emergencias_por_tipo_medico(%s);", (id_personal,))
            por_tipo = [{"tipo": r[0], "total": int(r[1])} for r in cur.fetchall()]

    return jsonify({
        "total": int(stats[0]) if stats else 0,
        "activas": int(stats[1]) if stats else 0,
        "ultima": stats[2].strftime('%d/%m/%Y') if stats and stats[2] else "—",
        "tipo_frecuente": stats[3] if stats else "—",
        "por_mes": por_mes,
        "por_tipo": por_tipo
    })


# ==========================================
# EMERGENCIAS - ATENDER / RESOLVER
# ==========================================

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


@app.route('/emergencias/resolver', methods=['POST'])
@login_required
def resolver_emergencia():
    id_evento = request.form.get('id_evento')
    with get_connection() as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("""
                    UPDATE evento_emergencia
                    SET id_estado_evento_fk = 'EST-003',
                        fecha_hora_egreso = NOW()
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
