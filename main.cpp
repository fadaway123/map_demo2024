#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlError>
#include "WebView2Item.h"
#include <windows.h>

int main(int argc, char *argv[])
{
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    QGuiApplication app(argc, argv);
    QFont f = app.font();
    f.setPointSizeF(f.pointSizeF() * 1.5);
    app.setFont(f);

    qmlRegisterType<WebView2Item>("map_demo2024", 1, 0,  "WebView2");

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

    engine.load(QUrl(QStringLiteral("qrc:/map_demo2024/Main.qml")));

    int ret = app.exec();

    CoUninitialize();
    return ret;
}