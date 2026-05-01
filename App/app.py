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

    return render_template('index.html',
                           total_pacientes=total_pacientes,
                           total_eventos=total_eventos,
                           eventos_activos=eventos_activos,
                           total_personal=total_personal)

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
    return render_template('emergencias.html', emergencias=lista_emergencias)

# ==========================================
# EMERGENCIAS - REGISTRAR (GET)
# ==========================================

@app.route('/registrar_emergencia', methods=['GET'])
@login_required
def registrar_emergencia():
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
    return render_template('registrar_emergencia.html',
                           pacientes=pacientes, tipos=tipos,
                           gravedades=gravedades, hospitales=hospitales,
                           salas=salas, personal=personal)

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
    cur = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur = conn.cursor(row_factory=psycopg.rows.dict_row)
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
    cur = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur = conn.cursor(row_factory=psycopg.rows.dict_row)
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
    cur = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur = conn.cursor(row_factory=psycopg.rows.dict_row)

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
    cur = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur = conn.cursor(row_factory=psycopg.rows.dict_row)
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
    cur = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur = conn.cursor(row_factory=psycopg.rows.dict_row)

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
    cur = None
    try:
        conn = psycopg.connect(**DB_CONFIG)
        cur = conn.cursor(row_factory=psycopg.rows.dict_row)
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
    return render_template('pacientes.html', pacientes=lista_pacientes)

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
# MAIN
# ==========================================

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
