# MongoDB Docker con Limitaciones de Recursos

Este proyecto configura MongoDB en Docker con limitaciones estrictas de recursos: **500MB de RAM** y **1 CPU**.

## Archivos incluidos

- `Dockerfile`: Imagen personalizada de MongoDB optimizada para uso limitado de memoria
- `docker-compose.yml`: Configuración con limitaciones de recursos
- `mongod.conf`: Configuración de MongoDB optimizada para bajo consumo de memoria
- `env.example`: Variables de entorno de ejemplo

## Características

- **Límite de memoria**: 500MB máximo
- **Límite de CPU**: 1 core máximo
- **Reservas**: 256MB RAM y 0.5 CPU como mínimo
- **Persistencia**: Volumen Docker para datos
- **Autenticación**: Habilitada con usuario admin
- **Optimización**: Cache de WiredTiger reducido a 100MB

## Uso

### Iniciar el contenedor
```bash
docker-compose up -d
```

### Ver logs
```bash
docker-compose logs -f mongodb
```

### Conectar a MongoDB
```bash
# Desde el host
mongo mongodb://admin:password123@localhost:27017/testdb

# Desde dentro del contenedor
docker exec -it mongodb-limited mongo -u admin -p password123
```

### Detener el contenedor
```bash
docker-compose down
```

### Detener y eliminar volúmenes
```bash
docker-compose down -v
```

## Monitoreo de recursos

Para verificar que las limitaciones se están aplicando:

```bash
# Ver uso de recursos del contenedor
docker stats mongodb-limited

# Ver detalles del contenedor
docker inspect mongodb-limited
```

## Configuración

Las variables de entorno se pueden modificar en el archivo `.env` o directamente en `docker-compose.yml`:

- `MONGO_INITDB_ROOT_USERNAME`: Usuario administrador
- `MONGO_INITDB_ROOT_PASSWORD`: Contraseña del administrador
- `MONGO_INITDB_DATABASE`: Base de datos inicial

## Notas importantes

- El cache de WiredTiger está limitado a 100MB para respetar el límite de 500MB
- La configuración está optimizada para desarrollo/testing
- Para producción, considera ajustar los límites según tus necesidades
