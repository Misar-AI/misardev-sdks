// Without this the project name comes from whatever directory the build runs
// in. The publication sets its artifactId explicitly, so published coordinates
// never depend on it — but the local jar name should not depend on the path.
rootProject.name = "misardev-kotlin"
