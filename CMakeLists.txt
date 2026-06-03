cmake_minimum_required(VERSION 3.16)
project(map_demo2024 VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_BUILD_TYPE Debug)
set(CMAKE_AUTOMOC_MOC_PREDEFS OFF)

find_package(Qt6 6.9.3 REQUIRED COMPONENTS Core Quick Network)

qt_standard_project_setup()

# 【正确顺序1：先创建目标】
qt_add_executable(appmap_demo2024
    main.cpp
    WebView2Item.h
    WebView2Item.cpp
)

# 【正确顺序2：再给目标设置属性】
# 不需要额外的include目录（exdisp.h等来自Windows SDK）

# QML模块
qt_add_qml_module(appmap_demo2024
    URI map_demo2024
    VERSION 1.0
    QML_FILES Main.qml
    RESOURCES resources.qrc
)

target_link_libraries(appmap_demo2024 PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::Network
    ole32
    oleaut32
)

install(TARGETS appmap_demo2024
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)