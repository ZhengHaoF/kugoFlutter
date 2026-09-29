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
    project.evaluationDependsOn(":app")
    // 插件子工程 compileSdk 对齐：file_picker 8.x 的 Android 模块锁死 34，
    // 而其依赖 flutter_plugin_android_lifecycle 新版 AAR 元数据要求 ≥36。
    // compileSdk 只影响编译期 API 面，不动 targetSdk / minSdk 的运行行为。
    // AGP 9 移除了 BaseExtension 旧 API，且根脚本拿不到 AGP 编译类，用反射设值；
    // :app 已被上面的 evaluationDependsOn 提前评估，不能再挂 afterEvaluate。
    if (project.name != "app") {
        afterEvaluate {
            val android =
                project.extensions.findByName("android") ?: return@afterEvaluate
            runCatching {
                // AGP 9 的 Kotlin DSL setter 是装箱 Integer，旧 AGP 是原始 int，
                // 按名字+参数个数匹配即可。
                val setCompileSdk = android.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdk" && it.parameterCount == 1
                }
                setCompileSdk?.invoke(android, 36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
