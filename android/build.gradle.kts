allprojects {
    repositories {
        google()
        mavenCentral()
    }
}


val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

println("Root build directory set to: ${newBuildDir.asFile.absolutePath}")

subprojects {

    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    println("Subproject '${project.name}' build directory: ${newSubprojectBuildDir.asFile.absolutePath}")

    if (project.name != "app") {
        project.evaluationDependsOn(":app")
    }
}
tasks.register<Delete>("clean") {
    delete(newBuildDir)
}
