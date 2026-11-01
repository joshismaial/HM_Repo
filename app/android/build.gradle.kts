allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Old plugins (e.g. geocoding_android) are compiled against an old Android version while their
// dependencies need 34+. Raise compileSdk for every plugin module (set by name, so it works on any Android Gradle Plugin version).
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android != null && project.name != "app") {
            try {
                android.javaClass.getMethod("setCompileSdk", Integer::class.javaObjectType).invoke(android, 36)
            } catch (e: Exception) {
                logger.warn("compileSdk override skipped for " + project.name + ": " + e.message)
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
