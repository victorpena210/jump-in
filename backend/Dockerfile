FROM maven:3.9.16-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn -B -ntp verify

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/target/jumpin-backend-0.3.0.jar app.jar
ENV BIND_ADDRESS=0.0.0.0
USER 10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
