# Redis Docker Setup

Este directorio contiene la configuración de Docker para Redis.

## Archivos incluidos

- `Dockerfile`: Imagen personalizada de Redis
- `docker-compose.yml`: Configuración de servicios
- `redis.conf`: Configuración de Redis
- `.env`: Variables de entorno (crear manualmente si es necesario)

## Uso

### Iniciar Redis
```bash
docker-compose up -d
```

### Detener Redis
```bash
docker-compose down
```

### Ver logs
```bash
docker-compose logs -f redis
```

## Servicios incluidos

1. **Redis Server** (puerto 6380)
   - Persistencia habilitada
   - Configuración personalizada
   - Sin autenticación

2. **Redis Commander** (puerto 8081)
   - Interfaz web para administrar Redis
   - Accesible en http://localhost:8081

## Configuración

- Los datos se persisten en el volumen `redis_data`
- La configuración se puede modificar en `redis.conf`
- Para habilitar autenticación, descomenta y configura `requirepass` en `redis.conf`

## Comandos útiles

```bash
# Conectar a Redis CLI (puerto 6380)
docker exec -it redis-server redis-cli -p 6379

# Conectar desde el anfitrión (puerto 6380)
redis-cli -p 6380

# Ver información del servidor
docker exec -it redis-server redis-cli info

# Limpiar datos
docker-compose down -v
```
