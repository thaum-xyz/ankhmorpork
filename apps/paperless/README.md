Configuration options: https://paperless-ngx.readthedocs.io/en/latest/configuration.html

// Required Services - https://paperless-ngx.readthedocs.io/en/latest/configuration.html#required-services
PAPERLESS_REDIS=redis://broker.paperless.svc:6379
PAPERLESS_DBHOST=db.paperless.svc
PAPERLESS_DBPORT=5432
PAPERLESS_DBNAME=paperless
PAPERLESS_DBUSER=<REDACTED>
PAPERLESS_DBPASS=<REDACTED>
PAPERLESS_DBSSLMODE=prefer

// Paths and folders - https://paperless-ngx.readthedocs.io/en/latest/configuration.html#paths-and-folders
PAPERLESS_CONSUMPTION_DIR
PAPERLESS_DATA_DIR
PAPERLESS_TRASH_DIR
PAPERLESS_MEDIA_ROOT
PAPERLESS_FILENAME_FORMAT={created_year}/{correspondent}/{asn} - {title}

// Security
PAPERLESS_SECRET_KEY=<REDACTED>
PAPERLESS_URL=https://papers.ankhmorpork.thaum.xyz
PAPERLESS_ALLOWED_HOSTS=paperless.paperless.svc,$(POD_IP) // As in https://github.com/korfuri/django-prometheus/issues/81#issuecomment-456210855
PAPERLESS_CORS_ALLOWED_HOSTS=paperless.paperless.svc
PAPERLESS_ADMIN_USER=<REDACTED>
PAPERLESS_ADMIN_PASSWORD=<REDACTED>
PAPERLESS_ADMIN_MAIL=<REDACTED>

// OCR settings - https://paperless-ngx.readthedocs.io/en/latest/configuration.html#ocr-settings
PAPERLESS_OCR_LANGUAGE=eng+deu+pol
PAPERLESS_OCR_LANGUAGES=pol  // additional languages

// Tika settings - https://paperless-ngx.readthedocs.io/en/latest/configuration.html#tika-settings
//PAPERLESS_TIKA_ENABLED=1
//PAPERLESS_TIKA_ENDPOINT=http://tika.paperless.svc:9998
//PAPERLESS_TIKA_GOTENBERG_ENDPOINT=http://gotenberg.paperless.svc:3000

// Software tweaks - https://paperless-ngx.readthedocs.io/en/latest/configuration.html#software-tweaks
PAPERLESS_TIME_ZONE=Europe/Berlin
PAPERLESS_CONSUMER_POLLING=30

PAPERLESS_TASK_WORKERS=1
PAPERLESS_WEBSERVER_WORKERS=1