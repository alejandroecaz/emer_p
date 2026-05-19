Que hace el programa?
---------------------
El programa es una aplicación web enfocada en la gestión hospitalaria y monitoreo de emergencias médicas en tiempo real, con implementación IoT y acceso a una base de datos PostgreSQL.

Integrantes del equipo
----------------------
| Nombre                                | Matrícula       |
| --------------------------------------| ----------------|
| Alejandro Evaristo Cazeres Escobedo   | 626337          |
| Marcelo Jasso Guzman                  | 628155          |
| Roberto De la Fuente                  | 593303          |
| Javier Oscar Wong Mora                | 628766          |

Paso a Paso para Levantar el Proyecto en Local
-----------------------------------------------
1. Clona o descarga el repositorio.

2. Instala Python y crea un entorno virtual:
    (Crear entorno virtual) python -m venv env
        (Activar en Windows) python -m venv env .\env\Scripts\activate 
        (Activar en Unix/Linux/MacOS) source env/bin/activate

3. Instala las dependencias necesarias:
    pip install -r requirements.txt

4. Configura PostgreSQL:
    Crear una base de datos llamada "emergencias".
    Crea un usuario llamado "emer_p", con contraseña "1234"
    Otorga permiso total del usuario "emer_p" a la visualización y modificación de la base de datos "emergencias".
    Restaurar el respaldo .sql incluido en el proyecto.
        psql -U emer_user -d emergencias -f emergencias_respaldo_final.sql

5. Configura MongoDB:
    Crear una base llamada sirape_analytics.
    Restaurar el respaldo .gz en el proyecto.
        mongostore --db sirape_analytics respaldofinal_sirape_analytics.gz
    
6. Ejecuta el servidor Flask
    python App/app.py

7. Abre tu navegador y visita `http://127.0.0.1:5000/`.

Credenciales de acceso:
    Usuario: admin
    Contraseña: 1234

Características Principales
---------------------------
- Autenticación de usuarios administrativos.
- Administrar pacientes y personal médico.
- Registrar y monitorear eventos de emergencia.
- Gestionar médicos, especialidades y turnos.
- Visualizar dashboards y KPIs analíticos.
- Integrar dispositivos IoT y beacons hospitalarios.
- Registrar ubicaciones de personal médico dentro del hospital.
- Generar alertas y notificaciones críticas.

Arquitectura del Proyecto
-------------------------
El sistema utiliza una arquitectura basada en Flask para la capa web y PostgreSQL como base de datos principal.

MongoDB se utiliza para almacenar métricas históricas y KPIs analíticos generados por el sistema.

La aplicación está organizada en:
- Rutas Flask (`app.py`)
- Plantillas HTML con Jinja2 (`templates/`)
- Recursos estáticos en App/static
- Procedimientos almacenados y funciones en PostgreSQL
- APIs JSON para dashboards y visualizaciones
- Integración IoT para monitoreo de ubicación y alertas

Pantallas de la Interfaz (GUI)
------------------------------
Autenticación:
- Inicio de sesión (`login.html`)

Dashboard Principal:
- Panel principal con estadísticas generales (`index.html`)

Gestión de Emergencias:
- Visualización de emergencias (`emergencias.html`)
- Registro de emergencias (`registrar_emergencias.html`)

Gestión Médica:
- Administración de médicos (`medicos.html`)
- Registro de médicos (`registrar_medico.html`)

Gestión de Pacientes:
- Consulta y administración de pacientes (`pacientes.html`)

Eventos Clínicos:
- Visualización de eventos médicos (`eventos.html`)

Personal Médico:
- Consulta de personal médico (`personal.html`)

Usuarios del Sistema:
- Administración de usuarios (`usuarios.html`)

IoT y Monitoreo:
- Panel de dispositivos IoT y alertas (`iot.html`)

Reportes y Analytics:
- Visualización de KPIs y métricas (`reportes.html`)

Pruebas (Testing)
-----------------
Pruebas unitarias y funcionales están en proceso.

Tecnologías Utilizadas
----------------------
- Python 3.10+
- Flask
- Jinja2
- PostgreSQL
- MongoDB
- Psycopg3
- PyMongo
- Highcharts
- HTML5
- CSS3
- JavaScript