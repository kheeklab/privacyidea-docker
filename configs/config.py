import os
import logging
import sys

SECRET_KEY = os.environ.get('SECRET_KEY')
if SECRET_KEY is None:
    print("SECRET_KEY not set! Refusing to start")
    sys.exit(1)

PI_PEPPER = os.environ.get('PI_PEPPER')
if PI_PEPPER is None:
    print("PI_PEPPER not set! Refusing to start")
    sys.exit(1)
# The realm, where users are allowed to login as administrators
SUPERUSER_REALM = os.environ.get('SUPERUSER_REALM', '['administrator']')
SQLALCHEMY_DATABASE_URI = os.environ.get('SQLALCHEMY_DATABASE_URI', 'sqlite:////data/privacyidea/privacyidea.db')
PI_ENCFILE = os.environ.get("PI_ENCFILE", "/data/privacyidea/encfile")
PI_HSM = os.environ.get("PI_HSM", "default")
PI_AUDIT_MODULE = os.environ.get("PI_AUDIT_MODULE", "privacyidea.lib.auditmodules.sqlaudit")
PI_AUDIT_KEY_PRIVATE = os.environ.get("PI_AUDIT_KEY_PRIVATE", "/data/privacyidea/keys/private.pem")
PI_AUDIT_KEY_PUBLIC = os.environ.get("PI_AUDIT_KEY_PUBLIC", "/data/privacyidea/keys/public.pem")
PI_LOGFILE = os.environ.get("PI_LOGFILE", "/data/privacyidea/privacyidea.log")
PI_LOGLEVEL = logging.getLevelName(os.environ.get("PI_LOGLEVEL", "INFO"))
PI_NODE = os.environ.get("HOSTNAME", "localnode")
CACHE_TYPE = os.environ.get("CACHE_TYPE", "simple")
PI_EXTERNAL_LINKS = os.environ.get("PI_EXTERNAL_LINKS", "True").lower() == "true"
# PI_GNUPG_HOME = "gpg"
# PI_LOGO = "otherlogo.png"
# PI_AUDIT_SQL_URI = sqlite://
PI_VASCO_LIBRARY = None
PI_ENGINE_REGISTRY_CLASS = os.environ.get("PI_ENGINE_REGISTRY_CLASS", "shared")
PI_PAGE_TITLE = os.environ.get("PI_PAGE_TITLE", "privacyIDEA Authentication System")
PI_AUDIT_SQL_TRUNCATE = True
