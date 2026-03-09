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
subprojects {
    project.evaluationDependsOn(":app")
}

// AGP 8+ requires every Android module to declare `namespace`.
// Some third-party Flutter plugins (e.g. isar_flutter_libs 3.1.0+1) may not yet set it,
// which breaks configuration. Set a safe default for known offenders.
subprojects {
    plugins.withId("com.android.library") {
        if (name != "isar_flutter_libs") return@withId

        val androidExt = extensions.findByName("android") ?: return@withId
        try {
            val namespaceProperty = androidExt.javaClass.getMethod("getNamespace")
            val setNamespaceMethod = androidExt.javaClass.getMethod("setNamespace", String::class.java)
            val current = namespaceProperty.invoke(androidExt) as? String
            if (current.isNullOrBlank()) {
                setNamespaceMethod.invoke(androidExt, "dev.isar.isar_flutter_libs")
            }
        } catch (_: Throwable) {
            // Ignore if AGP/extension API differs; build will surface any remaining issues.
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
