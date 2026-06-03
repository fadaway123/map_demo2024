#include "WebView2Item.h"
#include <QQuickWindow>
#include <QWindow>
#include <QDir>
#include <QDebug>
#include <QImage>
#include <QBuffer>
#include <cmath>

static QString extractAmapKey(const QByteArray &html)
{
    QRegularExpression re(QStringLiteral("(?<=key=)[^&\\s\"'<>]+"));
    auto match = re.match(QString::fromUtf8(html));
    return match.hasMatch() ? match.captured(0) : QString();
}

// IE11 渲染模式注册表设置
static void ensureIEMode()
{
    HKEY hKey;
    LPCWSTR subKey = L"Software\\Microsoft\\Internet Explorer\\Main\\FeatureControl\\FEATURE_BROWSER_EMULATION";
    if (RegOpenKeyEx(HKEY_CURRENT_USER, subKey, 0, KEY_SET_VALUE, &hKey) == ERROR_SUCCESS) {
        wchar_t exeName[MAX_PATH];
        GetModuleFileNameW(nullptr, exeName, MAX_PATH);
        LPCWSTR name = wcsrchr(exeName, L'\\');
        name = name ? name + 1 : exeName;
        DWORD value = 11001; // IE11 模式
        RegSetValueExW(hKey, name, 0, REG_DWORD, (BYTE*)&value, sizeof(value));
        RegCloseKey(hKey);
    }
}

WebView2Item::WebView2Item(QQuickItem *parent)
    : QQuickItem(parent)
{
    ensureIEMode();
    setFlag(ItemHasContents, true);
    m_resizeTimer = new QTimer(this);
    m_resizeTimer->setInterval(50);
    m_resizeTimer->setSingleShot(true);
    connect(m_resizeTimer, &QTimer::timeout, this, &WebView2Item::updateBrowserBounds);
    m_bridgeTimer = new QTimer(this);
    m_bridgeTimer->setInterval(50);
    connect(m_bridgeTimer, &QTimer::timeout, this, &WebView2Item::pollBridge);
    m_nam = new QNetworkAccessManager(this);
    loadConfig();
}

WebView2Item::~WebView2Item()
{
    if (m_connPoint && m_cookie)
        m_connPoint->Unadvise(m_cookie);
    if (m_connPoint) m_connPoint->Release();
    if (m_webBrowser) {
        m_webBrowser->Stop();
        m_webBrowser->put_Visible(FALSE);
        // 断开 OLE 容器链接
        IOleObject *ole = nullptr;
        if (SUCCEEDED(m_webBrowser->QueryInterface(IID_IOleObject, (void**)&ole))) {
            ole->Close(OLECLOSE_NOSAVE);
            ole->SetClientSite(nullptr);
            ole->Release();
        }
        m_webBrowser->Release();
    }
    if (m_clientSite) m_clientSite->Release();
    if (m_external) m_external->Release();
    if (m_eventSink) m_eventSink->Release();
    if (m_hwnd) DestroyWindow(m_hwnd);
}

void WebView2Item::componentComplete()
{
    QQuickItem::componentComplete();
    QTimer::singleShot(100, this, &WebView2Item::initializeBrowser);
}

void WebView2Item::initializeBrowser()
{
    if (m_initialized) return;

    QWindow *window = qobject_cast<QWindow*>(this->window());
    if (!window) {
        QTimer::singleShot(100, this, &WebView2Item::initializeBrowser);
        return;
    }
    m_parentHwnd = (HWND)window->winId();
    if (!m_parentHwnd) {
        QTimer::singleShot(100, this, &WebView2Item::initializeBrowser);
        return;
    }

    // 创建容器窗口
    WNDCLASSEXW wc = {0};
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"WebView2MessageWindow";
    RegisterClassExW(&wc);
    m_hwnd = CreateWindowExW(0, wc.lpszClassName, L"", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN,
                             0, 0, 1, 1, m_parentHwnd, nullptr, wc.hInstance, this);
    if (!m_hwnd) {
        qDebug() << "Failed to create container window";
        return;
    }
    SetWindowLongPtrW(m_hwnd, GWLP_USERDATA, (LONG_PTR)this);

    // 创建 IWebBrowser2 控件
    m_clientSite = new ClientSite(this);
    m_external = new ExternalDispatch(this);
    m_eventSink = new BrowserEventSink(this);

    HRESULT hr = CoCreateInstance(CLSID_WebBrowser, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_IWebBrowser2, (void**)&m_webBrowser);
    if (FAILED(hr)) {
        qDebug() << "Failed to create WebBrowser control:" << hr;
        return;
    }
    m_webBrowser->put_RegisterAsBrowser(TRUE);
    m_webBrowser->put_Visible(TRUE);
    m_webBrowser->put_Silent(TRUE);

    // 嵌入 OLE 控件
    IOleObject *oleObject = nullptr;
    hr = m_webBrowser->QueryInterface(IID_IOleObject, (void**)&oleObject);
    if (FAILED(hr)) {
        qDebug() << "Failed to get IOleObject";
        return;
    }
    oleObject->SetClientSite(m_clientSite);
    oleObject->DoVerb(OLEIVERB_INPLACEACTIVATE, nullptr, m_clientSite, 0, m_hwnd, nullptr);
    oleObject->Release();

    // 订阅 DWebBrowserEvents2
    IConnectionPointContainer *cpc = nullptr;
    if (SUCCEEDED(m_webBrowser->QueryInterface(IID_IConnectionPointContainer, (void**)&cpc))) {
        if (SUCCEEDED(cpc->FindConnectionPoint(DIID_DWebBrowserEvents2, &m_connPoint))) {
            m_connPoint->Advise(m_eventSink, &m_cookie);
        }
        cpc->Release();
    }

    m_initialized = true;

    // 延迟导航（等控件就绪）
    QTimer::singleShot(200, this, [this]() {
        if (!m_url.isEmpty())
            setUrl(m_url);
    });
}

void WebView2Item::updateBrowserBounds()
{
    if (!m_webBrowser || !isVisible()) return;

    QPointF itemPos = mapToScene(QPointF(0, 0));
    QSizeF itemSize = size();
    qreal dpr = window()->devicePixelRatio();

    RECT r;
    r.left = static_cast<LONG>(std::round(itemPos.x() * dpr));
    r.top = static_cast<LONG>(std::round(itemPos.y() * dpr));
    r.right = static_cast<LONG>(std::round((itemPos.x() + itemSize.width()) * dpr));
    r.bottom = static_cast<LONG>(std::round((itemPos.y() + itemSize.height()) * dpr));

    // 移动容器窗口
    SetWindowPos(m_hwnd, nullptr, r.left, r.top, r.right - r.left, r.bottom - r.top,
                 SWP_NOZORDER | SWP_NOACTIVATE);

    // 通知 OLE 控件调整大小
    IOleInPlaceObject *ipo = nullptr;
    if (SUCCEEDED(m_webBrowser->QueryInterface(IID_IOleInPlaceObject, (void**)&ipo))) {
        RECT cr = {0, 0, r.right - r.left, r.bottom - r.top};
        ipo->SetObjectRects(&cr, &cr);
        ipo->Release();
    }
}

void WebView2Item::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (m_webBrowser)
        m_resizeTimer->start();
}

void WebView2Item::itemChange(ItemChange change, const ItemChangeData &value)
{
    QQuickItem::itemChange(change, value);
    if (change == ItemVisibleHasChanged && m_webBrowser) {
        m_webBrowser->put_Visible(isVisible());
        if (isVisible())
            updateBrowserBounds();
    }
}

QUrl WebView2Item::url() const { return m_url; }

void WebView2Item::setUrl(const QUrl &url)
{
    m_url = url;
    if (!m_webBrowser) {
        emit urlChanged();
        return;
    }

    if (url.scheme() == QStringLiteral("qrc")) {
        QString resourcePath = QStringLiteral(":") + url.path();
        QString fileName = url.path().section(QLatin1Char('/'), -1);
        QString htmlDir = QDir::tempPath() + QStringLiteral("/MapDemoHtml");
        QDir().mkpath(htmlDir);
        QString filePath = htmlDir + QStringLiteral("/") + fileName;

        QByteArray htmlData;
        QFile resFile(resourcePath);
        if (resFile.open(QIODevice::ReadOnly)) {
            htmlData = resFile.readAll();
            bool needWrite = !QFile::exists(filePath);
            if (!needWrite) {
                QFile existing(filePath);
                if (existing.open(QIODevice::ReadOnly))
                    needWrite = existing.size() != htmlData.size();
            }
            if (needWrite) {
                QByteArray processed = htmlData;
                if (!m_configJsKey.isEmpty())
                    processed.replace("__AMAP_JS_KEY__", m_configJsKey.toUtf8());
                QFile outFile(filePath);
                if (outFile.open(QIODevice::WriteOnly))
                    outFile.write(processed);
            }
        }

        QString navUrl = QStringLiteral("file:///") + filePath;
        BSTR bstrUrl = SysAllocString((LPCWSTR)navUrl.utf16());
        m_webBrowser->Navigate(bstrUrl, nullptr, nullptr, nullptr, nullptr);
        SysFreeString(bstrUrl);
    } else {
        BSTR bstrUrl = SysAllocString((LPCWSTR)url.toString().utf16());
        m_webBrowser->Navigate(bstrUrl, nullptr, nullptr, nullptr, nullptr);
        SysFreeString(bstrUrl);
    }
    emit urlChanged();
}

void WebView2Item::loadConfig()
{
    QString configPath = QCoreApplication::applicationDirPath() + QStringLiteral("/config.json");
    QFile f(configPath);
    if (f.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
        QJsonObject obj = doc.object();
        m_configJsKey = obj[QStringLiteral("amapJsKey")].toString();
        QString webKey = obj[QStringLiteral("amapWebKey")].toString();
        if (!webKey.isEmpty())
            m_webServiceKey = webKey;
        f.close();
    } else {
        QJsonObject tmpl;
        tmpl[QStringLiteral("amapJsKey")] = QStringLiteral("你的高德 JS API Key");
        tmpl[QStringLiteral("amapWebKey")] = QStringLiteral("你的高德 Web Service Key");
        QFile outf(configPath);
        if (outf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            outf.write(QJsonDocument(tmpl).toJson(QJsonDocument::Indented));
            outf.close();
        }
    }
}

void WebView2Item::releaseBrowserFocus()
{
    if (m_parentHwnd)
        SetFocus(m_parentHwnd);
}

void WebView2Item::pollBridge()
{
    if (!m_webBrowser) return;

    IDispatch *dispDoc = nullptr;
    if (FAILED(m_webBrowser->get_Document(&dispDoc))) return;

    IHTMLDocument3 *doc3 = nullptr;
    if (FAILED(dispDoc->QueryInterface(IID_IHTMLDocument3, (void**)&doc3))) {
        dispDoc->Release();
        return;
    }

    IHTMLElement *el = nullptr;
    BSTR id = SysAllocString(L"__evt");
    if (SUCCEEDED(doc3->getElementById(id, &el))) {
        BSTR val = nullptr;
        el->get_innerText(&val);
        if (val && SysStringLen(val) > 0) {
            QString msg = QString::fromWCharArray(val);
            el->put_innerText(L"");

            if (msg.startsWith("dbl:")) {
                QStringList parts = msg.mid(4).split(',');
                if (parts.size() == 2) {
                    emit mapDblClicked(parts[0].toDouble(), parts[1].toDouble());
                }
            } else if (msg.startsWith("enter:")) {
                QStringList parts = msg.mid(6).split(',');
                if (parts.size() == 2) {
                    emit mapDblClicked(parts[0].toDouble(), parts[1].toDouble());
                }
            } else if (msg.startsWith("click:")) {
                QStringList parts = msg.mid(6).split(',');
                if (parts.size() == 2) {
                    emit mapClicked(parts[0].toDouble(), parts[1].toDouble());
                }
            } else if (msg.startsWith("move:")) {
                QStringList parts = msg.mid(5).split(',');
                if (parts.size() == 2) {
                    emit mouseMoved(parts[0].toDouble(), parts[1].toDouble());
                }
            } else if (msg.startsWith("marker:")) {
                QString title = msg.mid(7);
                emit markerClicked(title);
            } else if (msg.startsWith("regeo:")) {
                QStringList parts = msg.mid(6).split(',');
                if (parts.size() == 2)
                    cxxReGeocode(parts[0].toDouble(), parts[1].toDouble(), -1);
            } else if (msg.startsWith("annot:")) {
                int idx = msg.mid(6).toInt();
                emit annotationClicked(idx);
            } else if (msg.startsWith("jserr:")) {
                qDebug() << "[JS Error]" << msg.mid(6);
            } else if (msg.startsWith("pathcnt:")) {
                qDebug() << "[Path Markers]" << msg.mid(8);
            } else if (msg.startsWith("mkr:")) {
                qDebug() << "[Annot Marker]" << msg.mid(4);
            }
            emit bridgeEvent(msg);
        }
        SysFreeString(val);
        el->Release();
    }
    SysFreeString(id);
    doc3->Release();
    dispDoc->Release();
}

void WebView2Item::cxxGeocode(const QString &name, int which)
{
    if (m_webServiceKey.isEmpty()) return;
    QString url = QStringLiteral(
        "https://restapi.amap.com/v3/geocode/geo?key=%1&address=%2&output=json&city="
    ).arg(m_webServiceKey, QUrl::toPercentEncoding(name));

    QNetworkReply *reply = m_nam->get(QNetworkRequest(QUrl(url)));
    connect(reply, &QNetworkReply::finished, this, [this, reply, which]() {
        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonArray geocodes = doc.object()[QStringLiteral("geocodes")].toArray();
        if (!geocodes.isEmpty()) {
            QJsonObject g = geocodes[0].toObject();
            QString loc = g[QStringLiteral("location")].toString();
            QString addr = g[QStringLiteral("formatted_address")].toString();
            double lng = loc.section(QLatin1Char(','), 0, 0).toDouble();
            double lat = loc.section(QLatin1Char(','), 1, 1).toDouble();
            emit geocodeResult(lng, lat, addr, which);
        }
        reply->deleteLater();
    });
}

void WebView2Item::cxxReGeocode(double lng, double lat, int which)
{
    if (m_webServiceKey.isEmpty()) return;
    QString url = QStringLiteral(
        "https://restapi.amap.com/v3/geocode/regeo?key=%1&location=%2,%3&radius=1000&extensions=all&output=json"
    ).arg(m_webServiceKey).arg(lng, 0, 'f', 6).arg(lat, 0, 'f', 6);

    QNetworkReply *reply = m_nam->get(QNetworkRequest(QUrl(url)));
    connect(reply, &QNetworkReply::finished, this, [this, reply, lng, lat, which]() {
        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root = doc.object();
        QJsonObject regeocode = root[QStringLiteral("regeocode")].toObject();
        QJsonArray pois = regeocode[QStringLiteral("pois")].toArray();
        QString name;
        if (!pois.isEmpty())
            name = pois[0].toObject()[QStringLiteral("name")].toString();
        if (name.isEmpty())
            name = regeocode[QStringLiteral("formatted_address")].toString();
        if (name.isEmpty())
            name = QStringLiteral("未知位置");
        if (which == -1) {
            QString escaped(name);
            escaped.replace(QLatin1Char('\''), QStringLiteral("\\'"));
            escaped.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
            executeScript(QStringLiteral("setTooltipName('%1')").arg(escaped));
        } else {
            emit geocodeResult(lng, lat, name, which);
        }
        reply->deleteLater();
    });
}

void WebView2Item::cxxPlaceSearch(const QString &keywords)
{
    if (m_webServiceKey.isEmpty() || keywords.trimmed().isEmpty()) {
        emit placeSearchError(QStringLiteral("请输入关键词"));
        return;
    }
    QString url = QStringLiteral(
        "https://restapi.amap.com/v3/place/text?key=%1&keywords=%2&offset=10&output=json"
    ).arg(m_webServiceKey, QUrl::toPercentEncoding(keywords.trimmed()));

    QNetworkReply *reply = m_nam->get(QNetworkRequest(QUrl(url)));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root = doc.object();
        if (root[QStringLiteral("status")].toString() != QStringLiteral("1")) {
            emit placeSearchError(QStringLiteral("搜索失败: ") + root[QStringLiteral("info")].toString());
            reply->deleteLater();
            return;
        }
        QJsonArray pois = root[QStringLiteral("pois")].toArray();
        QVariantList results;
        for (const QJsonValue &v : pois) {
            QJsonObject p = v.toObject();
            QVariantMap item;
            item[QStringLiteral("name")] = p[QStringLiteral("name")].toString();
            item[QStringLiteral("address")] = p[QStringLiteral("address")].toString();
            item[QStringLiteral("location")] = p[QStringLiteral("location")].toString();
            item[QStringLiteral("type")] = p[QStringLiteral("type")].toString();
            results.append(item);
        }
        emit placeSearchResult(results);
        reply->deleteLater();
    });
}

void WebView2Item::cxxRouteSearch(double fLng, double fLat, double tLng, double tLat)
{
    if (m_webServiceKey.isEmpty()) { emit routeSearchError(QStringLiteral("Key 为空")); return; }
    QString url = QStringLiteral(
        "https://restapi.amap.com/v3/direction/driving?key=%1&origin=%2,%3&destination=%4,%5&extensions=all&output=json&strategy=0"
    ).arg(m_webServiceKey).arg(fLng, 0, 'f', 6).arg(fLat, 0, 'f', 6).arg(tLng, 0, 'f', 6).arg(tLat, 0, 'f', 6);

    QNetworkReply *reply = m_nam->get(QNetworkRequest(QUrl(url)));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (reply->error() != QNetworkReply::NoError) {
            QString err = QStringLiteral("网络请求失败: ") + reply->errorString();
            qDebug() << "[RouteSearch]" << err;
            emit routeSearchError(err);
            reply->deleteLater();
            return;
        }
        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root = doc.object();
        if (root[QStringLiteral("status")].toString() != QStringLiteral("1")) {
            QString info = root[QStringLiteral("info")].toString();
            qDebug() << "[RouteSearch] API error:" << info << "data:" << data.left(500);
            emit routeSearchError(QStringLiteral("路线规划失败: ") + info);
            reply->deleteLater();
            return;
        }
        QJsonObject route = root[QStringLiteral("route")].toObject();
        QJsonArray paths = route[QStringLiteral("paths")].toArray();
        if (paths.isEmpty()) {
            qDebug() << "[RouteSearch] 无可用路线, data:" << data.left(500);
            emit routeSearchError(QStringLiteral("无可用路线"));
            reply->deleteLater();
            return;
        }
        QJsonObject best = paths[0].toObject();
        double dist = best[QStringLiteral("distance")].toString().toDouble();
        int dur = static_cast<int>(best[QStringLiteral("duration")].toString().toDouble());
        QJsonArray steps = best[QStringLiteral("steps")].toArray();
        QJsonArray coords;
        for (const QJsonValue &sv : steps) {
            QString polyline = sv.toObject()[QStringLiteral("polyline")].toString();
            QStringList pts = polyline.split(QLatin1Char(';'));
            for (const QString &pt : pts) {
                QStringList xy = pt.split(QLatin1Char(','));
                if (xy.size() == 2) {
                    QJsonArray pair;
                    pair.append(xy[0].toDouble());
                    pair.append(xy[1].toDouble());
                    coords.append(pair);
                }
            }
        }
        QString json = QString::fromUtf8(QJsonDocument(coords).toJson(QJsonDocument::Compact));
        qDebug() << "[RouteSearch] 成功 坐标点数:" << coords.size() << "距离:" << dist << "时长:" << dur;
        emit routeSearchResult(json, dist, dur);
        reply->deleteLater();
    });
}

void WebView2Item::cxxWeather(const QString &city)
{
    if (m_webServiceKey.isEmpty() || city.isEmpty()) { emit weatherError(QStringLiteral("参数无效")); return; }
    QString url = QStringLiteral(
        "https://restapi.amap.com/v3/weather/weatherInfo?key=%1&city=%2&extensions=base&output=json"
    ).arg(m_webServiceKey, QUrl::toPercentEncoding(city));

    QNetworkReply *reply = m_nam->get(QNetworkRequest(QUrl(url)));
    connect(reply, &QNetworkReply::finished, this, [this, reply, city]() {
        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root = doc.object();
        if (root[QStringLiteral("status")].toString() != QStringLiteral("1")) {
            emit weatherError(QStringLiteral("天气查询失败: ") + root[QStringLiteral("info")].toString());
            reply->deleteLater();
            return;
        }
        QJsonArray lives = root[QStringLiteral("lives")].toArray();
        if (lives.isEmpty()) {
            emit weatherError(QStringLiteral("无天气数据"));
            reply->deleteLater();
            return;
        }
        QJsonObject live = lives[0].toObject();
        QString weather = live[QStringLiteral("weather")].toString();
        QString temp = live[QStringLiteral("temperature")].toString();
        emit weatherResult(city, weather, temp);
        reply->deleteLater();
    });
}

void WebView2Item::cxxSaveAnnotations(const QString &json)
{
    QFile f(QCoreApplication::applicationDirPath() + QStringLiteral("/annotations.json"));
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(json.toUtf8());
        f.close();
    }
}

QString WebView2Item::cxxLoadAnnotations()
{
    QFile f(QCoreApplication::applicationDirPath() + QStringLiteral("/annotations.json"));
    if (f.open(QIODevice::ReadOnly))
        return QString::fromUtf8(f.readAll());
    return QString();
}

QString WebView2Item::cxxImportImage(const QString &srcUrl)
{
    QString localPath = srcUrl;
    if (localPath.startsWith("file:///"))
        localPath = localPath.mid(8);

    QFileInfo fi(localPath);
    QString ext = fi.suffix().toLower();
    if (ext != "jpg" && ext != "jpeg" && ext != "png" && ext != "bmp" && ext != "gif")
        return {};

    QString dir = QCoreApplication::applicationDirPath() + QStringLiteral("/images");
    QDir().mkpath(dir);
    QString uuid = QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    QString destName = uuid + QStringLiteral(".") + ext;
    QString destPath = dir + QStringLiteral("/") + destName;
    QFile::copy(localPath, destPath);

    QImage img(localPath);
    if (img.isNull())
        return {};

    if (img.width() > 300 || img.height() > 300)
        img = img.scaled(300, 300, Qt::KeepAspectRatio, Qt::SmoothTransformation);

    QByteArray ba;
    QBuffer buf(&ba);
    buf.open(QIODevice::WriteOnly);
    img.save(&buf, ext == QStringLiteral("png") ? "PNG" : "JPEG", ext == QStringLiteral("png") ? -1 : 75);
    buf.close();

    QString mime = QStringLiteral("image/jpeg");
    if (ext == QStringLiteral("png")) mime = QStringLiteral("image/png");
    else if (ext == QStringLiteral("bmp")) mime = QStringLiteral("image/bmp");
    else if (ext == QStringLiteral("gif")) mime = QStringLiteral("image/gif");

    return QStringLiteral("data:") + mime + QStringLiteral(";base64,") + QString::fromLatin1(ba.toBase64());
}

QString WebView2Item::cxxOpenFileDialog()
{
    wchar_t buf[MAX_PATH] = {0};
    OPENFILENAMEW ofn = {0};
    ofn.lStructSize = sizeof(ofn);
    ofn.lpstrFilter = L"\u56fe\u7247\0*.jpg;*.jpeg;*.png;*.bmp;*.gif\0\0";
    ofn.lpstrFile = buf;
    ofn.nMaxFile = MAX_PATH;
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY | OFN_NOCHANGEDIR;
    if (!GetOpenFileNameW(&ofn))
        return {};

    QString path = QString::fromWCharArray(buf);
    QFileInfo fi(path);
    QString ext = fi.suffix().toLower();

    QImage img(path);
    if (img.isNull()) return {};

    if (img.width() > 300 || img.height() > 300)
        img = img.scaled(300, 300, Qt::KeepAspectRatio, Qt::SmoothTransformation);

    QByteArray ba;
    QBuffer buf2(&ba);
    buf2.open(QIODevice::WriteOnly);
    img.save(&buf2, ext == QStringLiteral("png") ? "PNG" : "JPEG", ext == QStringLiteral("png") ? -1 : 75);
    buf2.close();

    QString dir = QCoreApplication::applicationDirPath() + QStringLiteral("/images");
    QDir().mkpath(dir);
    QString uuid = QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    QString destName = uuid + QStringLiteral(".") + ext;
    QString destPath = dir + QStringLiteral("/") + destName;
    QFile::copy(path, destPath);

    QString mime = QStringLiteral("image/jpeg");
    if (ext == QStringLiteral("png")) mime = QStringLiteral("image/png");
    else if (ext == QStringLiteral("bmp")) mime = QStringLiteral("image/bmp");
    else if (ext == QStringLiteral("gif")) mime = QStringLiteral("image/gif");

    QJsonObject ret;
    ret[QStringLiteral("dataUri")] = QStringLiteral("data:") + mime + QStringLiteral(";base64,") + QString::fromLatin1(ba.toBase64());
    ret[QStringLiteral("relPath")] = QStringLiteral("images/") + destName;
    return QString::fromUtf8(QJsonDocument(ret).toJson(QJsonDocument::Compact));
}

QString WebView2Item::cxxImageFullPath(const QString &relPath)
{
    return QCoreApplication::applicationDirPath() + QStringLiteral("/") + relPath;
}

QString WebView2Item::cxxReadImageBase64(const QString &relPath)
{
    QString fullPath = QCoreApplication::applicationDirPath() + QStringLiteral("/") + relPath;
    QFile f(fullPath);
    if (!f.open(QIODevice::ReadOnly))
        return {};

    QByteArray data = f.readAll();
    QFileInfo fi(fullPath);
    QString ext = fi.suffix().toLower();
    QString mime = QStringLiteral("image/jpeg");
    if (ext == QStringLiteral("png")) mime = QStringLiteral("image/png");
    else if (ext == QStringLiteral("bmp")) mime = QStringLiteral("image/bmp");
    else if (ext == QStringLiteral("gif")) mime = QStringLiteral("image/gif");

    return QStringLiteral("data:") + mime + QStringLiteral(";base64,") + QString::fromLatin1(data.toBase64());
}

void WebView2Item::executeScript(const QString &script)
{
    if (!m_webBrowser) return;

    IDispatch *dispDoc = nullptr;
    m_webBrowser->get_Document(&dispDoc);
    if (!dispDoc) return;

    IHTMLDocument2 *doc = nullptr;
    if (FAILED(dispDoc->QueryInterface(IID_IHTMLDocument2, (void**)&doc))) {
        dispDoc->Release();
        return;
    }

    IDispatch *dispWindow = nullptr;
    doc->get_Script(&dispWindow);
    doc->Release();
    if (!dispWindow) { dispDoc->Release(); return; }

    IHTMLWindow2 *win = nullptr;
    if (SUCCEEDED(dispWindow->QueryInterface(IID_IHTMLWindow2, (void**)&win))) {
        BSTR bstrScript = SysAllocString((LPCWSTR)script.utf16());
        BSTR bstrLang = SysAllocString(L"JavaScript");
        VARIANT v;
        VariantInit(&v);
        win->execScript(bstrScript, bstrLang, &v);
        SysFreeString(bstrScript);
        SysFreeString(bstrLang);
        win->Release();
    }
    dispWindow->Release();
    dispDoc->Release();
}

LRESULT CALLBACK WebView2Item::WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    WebView2Item *self = (WebView2Item*)GetWindowLongPtrW(hWnd, GWLP_USERDATA);
    if (!self) return DefWindowProcW(hWnd, msg, wParam, lParam);

    switch (msg) {
    case WM_SIZE:
        self->updateBrowserBounds();
        break;
    case WM_SETFOCUS:
        if (self->m_parentHwnd) SetFocus(self->m_parentHwnd);
        return 0;
    default:
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }
    return 0;
}

// ============================================================================
// InPlaceFrame — IOleInPlaceFrame (独立类，避免 EnableModeless 冲突)
// ============================================================================

HRESULT WebView2Item::InPlaceFrame::QueryInterface(REFIID riid, void **ppv)
{
    *ppv = nullptr;
    if (riid == IID_IUnknown || riid == IID_IOleInPlaceFrame || riid == IID_IOleInPlaceUIWindow)
        *ppv = (IOleInPlaceFrame*)this;
    else
        return E_NOINTERFACE;
    AddRef();
    return S_OK;
}

ULONG WebView2Item::InPlaceFrame::Release()
{
    ULONG count = --refCount;
    // 不 delete — 嵌入在 ClientSite 中，生命周期由 ClientSite 管理
    return count;
}

HRESULT WebView2Item::InPlaceFrame::GetWindow(HWND *phwnd)
{
    *phwnd = self ? self->m_hwnd : nullptr;
    return *phwnd ? S_OK : E_NOTIMPL;
}

// ============================================================================
// ClientSite — 多接口宿主
// ============================================================================

HRESULT WebView2Item::ClientSite::QueryInterface(REFIID riid, void **ppv)
{
    *ppv = nullptr;
    if (riid == IID_IUnknown || riid == IID_IOleClientSite)
        *ppv = (IOleClientSite*)this;
    else if (riid == IID_IOleInPlaceSite)
        *ppv = (IOleInPlaceSite*)this;
    else if (riid == IID_IOleInPlaceFrame)
        *ppv = (IOleInPlaceFrame*)&frame;
    else if (riid == IID_IDocHostUIHandler)
        *ppv = (IDocHostUIHandler*)this;
    else if (riid == IID_IServiceProvider)
        *ppv = (IServiceProvider*)this;
    else
        return E_NOINTERFACE;
    AddRef();
    return S_OK;
}

ULONG WebView2Item::ClientSite::Release()
{
    ULONG count = --refCount;
    if (count == 0) delete this;
    return count;
}

HRESULT WebView2Item::ClientSite::GetContainer(IOleContainer **ppContainer)
{
    *ppContainer = nullptr;
    return E_NOTIMPL;
}

HRESULT WebView2Item::ClientSite::GetWindow(HWND *phwnd)
{
    *phwnd = self->m_hwnd;
    return S_OK;
}

HRESULT WebView2Item::ClientSite::GetWindowContext(
    IOleInPlaceFrame **ppFrame, IOleInPlaceUIWindow **ppUI,
    LPRECT lprcPos, LPRECT lprcClip, LPOLEINPLACEFRAMEINFO lpFrameInfo)
{
    *ppFrame = (IOleInPlaceFrame*)&frame;
    frame.AddRef();
    *ppUI = nullptr;
    if (lprcPos) {
        RECT r;
        GetClientRect(self->m_hwnd, &r);
        *lprcPos = r;
        *lprcClip = r;
    }
    if (lpFrameInfo) {
        lpFrameInfo->fMDIApp = FALSE;
        lpFrameInfo->hwndFrame = self->m_hwnd;
        lpFrameInfo->haccel = nullptr;
        lpFrameInfo->cAccelEntries = 0;
    }
    return S_OK;
}

HRESULT WebView2Item::ClientSite::OnPosRectChange(LPCRECT)
{
    return S_OK;
}

HRESULT WebView2Item::ClientSite::GetHostInfo(DOCHOSTUIINFO *pInfo)
{
    pInfo->cbSize = sizeof(DOCHOSTUIINFO);
    pInfo->dwFlags = DOCHOSTUIFLAG_NO3DBORDER | 0x01000000;
    pInfo->dwDoubleClick = DOCHOSTUIDBLCLK_DEFAULT;
    return S_OK;
}

HRESULT WebView2Item::ClientSite::GetExternal(IDispatch **ppDispatch)
{
    *ppDispatch = self->m_external;
    self->m_external->AddRef();
    return S_OK;
}

HRESULT WebView2Item::ClientSite::QueryService(REFGUID guidService, REFIID riid, void **ppv)
{
    return QueryInterface(riid, ppv);
}

// ============================================================================
// ExternalDispatch — JS → C++ 通信
// ============================================================================

HRESULT WebView2Item::ExternalDispatch::GetIDsOfNames(REFIID, LPOLESTR *rgszNames, UINT cNames, LCID, DISPID *rgDispId)
{
    if (cNames > 0 && rgszNames && rgDispId) {
        if (wcscmp(rgszNames[0], L"onMapClick") == 0)       { *rgDispId = 1; return S_OK; }
        if (wcscmp(rgszNames[0], L"onMarkerClick") == 0)    { *rgDispId = 2; return S_OK; }
        if (wcscmp(rgszNames[0], L"onMapDblClick") == 0)    { *rgDispId = 3; return S_OK; }
        if (wcscmp(rgszNames[0], L"onGeocodeResult") == 0)  { *rgDispId = 4; return S_OK; }
        if (wcscmp(rgszNames[0], L"onMouseMove") == 0)      { *rgDispId = 5; return S_OK; }
    }
    return E_NOTIMPL;
}

HRESULT WebView2Item::ExternalDispatch::QueryInterface(REFIID riid, void **ppv)
{
    *ppv = nullptr;
    if (riid == IID_IUnknown || riid == IID_IDispatch) {
        *ppv = this;
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

ULONG WebView2Item::ExternalDispatch::Release()
{
    ULONG count = --refCount;
    if (count == 0) delete this;
    return count;
}

HRESULT WebView2Item::ExternalDispatch::Invoke(
    DISPID dispIdMember, REFIID, LCID, WORD wFlags,
    DISPPARAMS *pDispParams, VARIANT *pVarResult, EXCEPINFO *, UINT *)
{
    // onMapClick(lng, lat)
    if (dispIdMember == 1 && pDispParams->cArgs == 2) {
        double lng = pDispParams->rgvarg[1].dblVal;
        double lat = pDispParams->rgvarg[0].dblVal;
        QMetaObject::invokeMethod(self, [this, lng, lat]() {
            emit self->mapClicked(lng, lat);
        }, Qt::QueuedConnection);
        return S_OK;
    }

    // onMarkerClick(title)
    if (dispIdMember == 2 && pDispParams->cArgs == 1) {
        QString title = QString::fromWCharArray(pDispParams->rgvarg[0].bstrVal);
        QMetaObject::invokeMethod(self, [this, title]() {
            emit self->markerClicked(title);
        }, Qt::QueuedConnection);
        return S_OK;
    }

    // onMapDblClick(lng, lat)
    if (dispIdMember == 3 && pDispParams->cArgs == 2) {
        double lng = pDispParams->rgvarg[1].dblVal;
        double lat = pDispParams->rgvarg[0].dblVal;
        QMetaObject::invokeMethod(self, [this, lng, lat]() {
            emit self->mapDblClicked(lng, lat);
        }, Qt::QueuedConnection);
        return S_OK;
    }

    // onMouseMove(lng, lat)
    if (dispIdMember == 5 && pDispParams->cArgs == 2) {
        double lng = pDispParams->rgvarg[1].dblVal;
        double lat = pDispParams->rgvarg[0].dblVal;
        QMetaObject::invokeMethod(self, [this, lng, lat]() {
            emit self->mouseMoved(lng, lat);
        }, Qt::QueuedConnection);
        return S_OK;
    }

    // onGeocodeResult(lng, lat, name, which)
    if (dispIdMember == 4 && pDispParams->cArgs == 4) {
        double lng = pDispParams->rgvarg[3].dblVal;
        double lat = pDispParams->rgvarg[2].dblVal;
        QString name = QString::fromWCharArray(pDispParams->rgvarg[1].bstrVal);
        int which = static_cast<int>(pDispParams->rgvarg[0].dblVal);
        QMetaObject::invokeMethod(self, [this, lng, lat, name, which]() {
            emit self->geocodeResult(lng, lat, name, which);
        }, Qt::QueuedConnection);
        return S_OK;
    }

    return E_NOTIMPL;
}

// ============================================================================
// BrowserEventSink — 监听导航完成等事件
// ============================================================================

HRESULT WebView2Item::BrowserEventSink::QueryInterface(REFIID riid, void **ppv)
{
    *ppv = nullptr;
    if (riid == IID_IUnknown || riid == DIID_DWebBrowserEvents2) {
        *ppv = this;
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

ULONG WebView2Item::BrowserEventSink::Release()
{
    ULONG count = --refCount;
    if (count == 0) delete this;
    return count;
}

HRESULT WebView2Item::BrowserEventSink::Invoke(
    DISPID dispIdMember, REFIID, LCID, WORD,
    DISPPARAMS *pDispParams, VARIANT *, EXCEPINFO *, UINT *)
{
    if (dispIdMember == DISPID_DOCUMENTCOMPLETE) {
        QMetaObject::invokeMethod(self, [this]() {
            self->updateBrowserBounds();
            self->m_bridgeTimer->start();
            emit self->pageLoaded();
        }, Qt::QueuedConnection);
    }
    return S_OK;
}
