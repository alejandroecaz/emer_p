Que hace el programa?
---------------------
El programa es una aplicación web que permite a los administradores iniciar sesión y gestionar información de médicos. La autenticación se realiza mediante credenciales específicas, y la interfaz proporciona funcionalidades para cargar y editar datos de médicos.

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
4. Ejecuta el servidor Flask
    python App/app.py
5. Abre tu navegador y visita `http://127.0.0.1:5000/`.

Características Principales
---------------------------
- Autenticación de usuarios administrativos.
- Gestionar información de médicos (cargar, editar datos).

Arquitectura del Proyecto
-------------------------
El proyecto utiliza Flask como marco web para crear la aplicación y Jinja2 para plantillas HTML. La lógica de autenticación se encuentra en `App/app.py` mientras que las vistas y formularios están en los archivos `.html` dentro de `App/templates`.

Pantallas de la Interfaz (GUI)
------------------------------
- Pantalla de inicio de sesión (`login.html`)
- Pantalla para gestión de médicos (`medicos.html`)

Pruebas (Testing)
-----------------
Pruebas unitarias y funcionales están en proceso.

Tecnologías Utilizadas
----------------------
- Python 3.10+
- Flask
- Jinja2
- PostgreSQL