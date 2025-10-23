// android/build.gradle.kts
import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory

// 🔑 No plugins {} block here — the Flutter loader is applied in settings.gradle.kts

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// (Optional) Keep shared /build directory at repo root
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    layout.buildDirectory.set(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
