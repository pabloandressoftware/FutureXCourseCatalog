#!/usr/bin/env bash
# Compila y levanta Eureka (8761), fx-course-service (8001) y fx-catalog-service (8002).
cd "$(dirname "$0")/.."
mkdir -p logs
start() { # nombre jar
  nohup java -jar "$2" > "logs/$1.log" 2>&1 &
  echo $! > "logs/$1.pid"
  echo "$1 -> pid $(cat logs/$1.pid)"
}
for d in fx-discovery-server fx-course-service fx-catalog-service; do (cd $d && mvn -q -DskipTests package); done
start eureka  fx-discovery-server/target/FutureXEurekaServer-0.0.1-SNAPSHOT.jar
sleep 25
start course  fx-course-service/target/FutureXCourseApp-0.0.1-SNAPSHOT.jar
start catalog fx-catalog-service/target/FutureXCourseCatalog-0.0.1-SNAPSHOT.jar
