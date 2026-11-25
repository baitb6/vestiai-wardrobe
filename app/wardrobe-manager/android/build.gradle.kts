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

// 旧插件 compileSdk 兜底：file_picker 8.x 的 AAR 仍按 android-34 编译，
// 而 flutter_plugin_android_lifecycle 要求宿主 36+；统一抬到 36 过 AAR 元数据检查。
// 反射调用避免 root 脚本引入 android gradle 插件类型。
subprojects {
    // 只抬插件子模块（app 已显式 compileSdk=36）；AGP 9 用 setCompileSdk(Int) 属性
    if (name != "app") {
        afterEvaluate {
            extensions.findByName("android")?.let { ext ->
                try {
                    val m = ext.javaClass.methods.firstOrNull {
                        it.name == "setCompileSdk" && it.parameterCount == 1 &&
                                (it.parameterTypes[0] == java.lang.Integer.TYPE ||
                                        it.parameterTypes[0] == java.lang.Integer::class.java)
                    }
                    m?.invoke(ext, 36)
                } catch (_: Exception) {
                }
            }
        }
    }
}

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
