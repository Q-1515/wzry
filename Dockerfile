FROM openjdk:8-jre-slim

WORKDIR /app

# Copy application files
COPY home-server-0.0.1-SNAPSHOT.jar /app/home-server-0.0.1-SNAPSHOT.jar
COPY index.html /app/index.html
COPY layui /app/layui

# Expose application port
EXPOSE 8888

# Default JVM options (can be overridden at runtime)
ENV JAVA_OPTS="-Xmx1024M -Xms256M"

# Run the jar
CMD ["sh","-c","exec java $JAVA_OPTS -jar /app/home-server-0.0.1-SNAPSHOT.jar"]
