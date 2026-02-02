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
    // 1. Solución para el Namespace
    val fixNamespace = {
        val android = project.extensions.findByName("android")
        if (android != null) {
            try {
                val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                if (project.name.contains("on_audio_query")) {
                    setNamespace.invoke(android, "com.lucasjosino.on_audio_query")
                } else {
                    val getNamespace = android.javaClass.getMethod("getNamespace")
                    if (getNamespace.invoke(android) == null) {
                        setNamespace.invoke(android, "com.example.lumina_player.${project.name.replace("-", "_")}")
                    }
                }
            } catch (e: Exception) {}
        }
    }

    // 2. Solución para JVM Target usando la nueva sintaxis compilerOptions (Kotlin 2.0+)
    val fixJvmTarget = {
        val android = project.extensions.findByName("android")
        if (android != null) {
            val base = android as com.android.build.gradle.BaseExtension
            base.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        
        // Nueva forma obligatoria en Kotlin 2.x
        project.tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile::class.java).configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }

    project.plugins.withId("com.android.library") { 
        fixNamespace()
        fixJvmTarget()
    }
    project.plugins.withId("com.android.application") { 
        fixNamespace()
        fixJvmTarget()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
