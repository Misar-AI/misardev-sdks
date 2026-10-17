import com.vanniktech.maven.publish.SonatypeHost
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("jvm") version "2.1.21"
    `java-library`
    // NOT `maven-publish` + `signing`. Those upload by PUTting each file to the
    // repository URL, but https://central.sonatype.com/api/v1/publisher/upload is
    // a bundle POST API, not a Maven repo — every PUT 404s and nothing is ever
    // published. This plugin speaks the Central Portal protocol.
    id("com.vanniktech.maven.publish") version "0.30.0"
}

group = "io.misar"
version = "1.0.0"

repositories {
    mavenCentral()
}

dependencies {
    // `api`, not `implementation`: streams return Flow and every call returns a
    // Jackson JsonNode, so both types are part of this library's ABI. Under
    // `implementation` the POM scopes them to runtime and a consumer cannot
    // compile against the published artifact.
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
    api("com.fasterxml.jackson.core:jackson-databind:2.18.9")
    testImplementation(kotlin("test"))
    testImplementation(kotlin("reflect"))
    // Gradle 9 no longer puts the JUnit Platform launcher on the test runtime
    // classpath implicitly. Without it `gradle test` dies with "Failed to load
    // JUnit Platform" before running a single test.
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

// Bytecode for Java 11+, whatever JDK builds it — the client only needs java.net.http.
java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

tasks.test {
    useJUnitPlatform()
}

// The sources and javadoc jars Central requires are produced by the publishing
// plugin, so declaring them here too would build two artifacts per classifier.

mavenPublishing {
    publishToMavenCentral(SonatypeHost.CENTRAL_PORTAL, automaticRelease = true)
    signAllPublications()
    coordinates("io.misar", "misardev-kotlin", version.toString())

    pom {
        name.set("MisarDev Kotlin SDK")
        description.set(
            "Build, ship and run apps on Misar.Dev from Kotlin: projects, files, builds, " +
                "deploys, domains, templates, OpenAI-compatible chat completions, code search, " +
                "organizations and billing — suspend functions, retries, typed plan-limit " +
                "errors, Flow SSE streams and pagination."
        )
        url.set("https://www.misar.dev")
        inceptionYear.set("2026")
        organization {
            name.set("Misar.AI")
            url.set("https://misar.io")
        }
        licenses {
            license {
                name.set("MIT License")
                url.set("https://opensource.org/licenses/MIT")
                distribution.set("repo")
            }
        }
        developers {
            developer {
                id.set("misar-ai")
                name.set("Misar.AI")
                email.set("hello@misar.io")
                organization.set("Misar.AI")
                organizationUrl.set("https://misar.io")
            }
        }
        scm {
            connection.set("scm:git:git://github.com/Misar-AI/misardev-sdks.git")
            developerConnection.set("scm:git:ssh://github.com/Misar-AI/misardev-sdks.git")
            url.set("https://github.com/Misar-AI/misardev-sdks/tree/main/kotlin")
        }
        issueManagement {
            system.set("GitHub Issues")
            url.set("https://github.com/Misar-AI/misardev-sdks/issues")
        }
        // A Maven POM has no "documentation" element. The product docs live at
        // https://docs.misar.io/dev and are linked from the README.
    }
}
