import com.android.build.api.dsl.LibraryExtension
import com.android.build.api.variant.AndroidComponentsExtension
import com.android.build.api.variant.LibraryVariant
import com.android.build.api.variant.LibraryVariantBuilder

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

// isar_flutter_libs 3.1.0+1 is a legacy plugin that still pins compileSdkVersion 30.
// Override it after the plugin's DSL is configured, but before AGP creates variants.
subprojects {
    plugins.withId("com.android.library") {
        if (name != "isar_flutter_libs") return@withId

        extensions.configure<
            AndroidComponentsExtension<LibraryExtension, LibraryVariantBuilder, LibraryVariant>,
        >("androidComponents") {
            finalizeDsl { extension ->
                if (extension.namespace.isNullOrBlank()) {
                    extension.namespace = "dev.isar.isar_flutter_libs"
                }
                extension.compileSdk = 35
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
