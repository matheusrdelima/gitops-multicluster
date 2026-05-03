package com.example.hello;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Map;

@RestController
public class HelloController {

    private static final Logger log = LoggerFactory.getLogger(HelloController.class);

    @Value("${app.version:unknown}")
    private String appVersion;

    @Value("${POD_NAME:unknown-pod}")
    private String podName;

    @Value("${CLUSTER_NAME:unknown-cluster}")
    private String clusterName;

    @Value("${TRAFFIC_ROLE:unknown}")
    private String trafficRole;

    @GetMapping("/hello")
    public Map<String, Object> hello() {
        // Log estruturado com TRAFFIC_ROLE para identificar shadow vs real
        log.info("[{}][{}][{}][ROLE:{}] /hello endpoint chamado",
                appVersion, clusterName, podName, trafficRole);

        return Map.of(
            "message",       "Hello from " + appVersion + "!",
            "version",       appVersion,
            "pod",           podName,
            "cluster",       clusterName,
            "trafficRole",   trafficRole,
            "timestamp",     Instant.now().toString(),
            "isShadow",      "shadow".equalsIgnoreCase(trafficRole)
        );
    }

    @GetMapping("/actuator/health/readiness")
    public Map<String, String> readiness() {
        return Map.of("status", "UP");
    }

    @GetMapping("/actuator/health/liveness")
    public Map<String, String> liveness() {
        return Map.of("status", "UP");
    }
}
