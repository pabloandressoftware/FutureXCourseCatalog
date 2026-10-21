package com.futurex.services.FutureXCourseCatalog;

import com.netflix.appinfo.InstanceInfo;
import com.netflix.discovery.EurekaClient;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.ratelimiter.RequestNotPermitted;
import io.github.resilience4j.ratelimiter.annotation.RateLimiter;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

@RestController
public class CatalogController {

    private static final Logger log = LoggerFactory.getLogger(CatalogController.class);

    /** Nombre con el que fx-course-service se registra en Eureka (spring.application.name). */
    private static final String COURSE_SERVICE_ID = "fx-course-service";

    private final EurekaClient client;
    private final RestTemplate restTemplate;

    public CatalogController(EurekaClient client, RestTemplate restTemplate) {
        this.client = client;
        this.restTemplate = restTemplate;
    }

    /**
     * Service Discovery: pregunta a Eureka por una instancia de fx-course-service
     * y devuelve su URL base (termina en "/").
     */
    private String courseServiceUrl() {
        InstanceInfo instanceInfo = client.getNextServerFromEureka(COURSE_SERVICE_ID, false);
        return instanceInfo.getHomePageUrl();
    }

    @GetMapping("/")
    @CircuitBreaker(name = "courseService", fallbackMethod = "fallbackGetCatalogHome")
    public String getCatalogHome() {
        String courseAppMessage = restTemplate.getForObject(courseServiceUrl(), String.class);
        return "Welcome to FutureX Course Catalog " + courseAppMessage;
    }

    // El fallback va en @Retry (la anotación más externa): si estuviera en @CircuitBreaker
    // el error quedaría absorbido y @Retry nunca llegaría a reintentar.
    @GetMapping("/catalog")
    @Retry(name = "courseService", fallbackMethod = "fallbackGetCatalog")
    @CircuitBreaker(name = "courseService")
    public String getCatalog() {
        String courses = restTemplate.getForObject(courseServiceUrl() + "courses", String.class);
        return "Our courses are " + courses;
    }

    @GetMapping("/firstcourse")
    @CircuitBreaker(name = "courseService", fallbackMethod = "fallbackGetSpecificCourse")
    @RateLimiter(name = "courseService")
    public String getSpecificCourse() {
        Course course = restTemplate.getForObject(courseServiceUrl() + "1", Course.class);
        return "Our first course is " + course.getCoursename();
    }

    // ---- Métodos de fallback (misma firma + el Exception como último parámetro) ----

    public String fallbackGetCatalogHome(Exception ex) {
        log.warn("fallbackGetCatalogHome: {}", ex.toString());
        return "Fallback: Welcome to FutureX Course Catalog, but the course service is not available (" + reason(ex) + ").";
    }

    public String fallbackGetCatalog(Exception ex) {
        log.warn("fallbackGetCatalog: {}", ex.toString());
        return "Fallback: Unable to retrieve course catalog (" + reason(ex) + ").";
    }

    public String fallbackGetSpecificCourse(Exception ex) {
        log.warn("fallbackGetSpecificCourse: {}", ex.toString());
        return "Fallback: Unable to retrieve the first course (" + reason(ex) + ").";
    }

    private String reason(Exception ex) {
        if (ex instanceof CallNotPermittedException) {
            return "circuit breaker is OPEN";
        }
        if (ex instanceof RequestNotPermitted) {
            return "rate limit exceeded";
        }
        return "course service unavailable";
    }
}
