#pragma once

#include <QQuickItem>
#include <QTimer>
#include <QUrl>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QUuid>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QRegularExpression>
#include <windows.h>
#include <exdisp.h>
#include <mshtml.h>
#include <docobj.h>
#include <exdispid.h>
#include <mshtmhst.h>
#include <mshtmdid.h>
#include <servprov.h>

class WebView2Item : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QUrl url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(QString webServiceKey READ webServiceKey WRITE setWebServiceKey NOTIFY webServiceKeyChanged)

public:
    WebView2Item(QQuickItem *parent = nullptr);
    ~WebView2Item() override;

    QUrl url() const;
    void setUrl(const QUrl &url);
    QString webServiceKey() const { return m_webServiceKey; }
    void setWebServiceKey(const QString &key) { m_webServiceKey = key; emit webServiceKeyChanged(); }

public slots:
    void executeScript(const QString &script);
    void releaseBrowserFocus();

    Q_INVOKABLE void cxxGeocode(const QString &name, int which);
    Q_INVOKABLE void cxxReGeocode(double lng, double lat, int which);
    Q_INVOKABLE void cxxPlaceSearch(const QString &keywords);
    Q_INVOKABLE void cxxRouteSearch(double fLng, double fLat, double tLng, double tLat);
    Q_INVOKABLE void cxxWeather(const QString &city);
    Q_INVOKABLE void cxxSaveAnnotations(const QString &json);
    Q_INVOKABLE QString cxxLoadAnnotations();
    Q_INVOKABLE QString cxxImportImage(const QString &srcUrl);
    Q_INVOKABLE QString cxxOpenFileDialog();
    Q_INVOKABLE QString cxxImageFullPath(const QString &relPath);
    Q_INVOKABLE QString cxxReadImageBase64(const QString &relPath);
    Q_INVOKABLE QString cxxSaveConfig(const QString &domain, const QString &jsKey, const QString &webKey);
    Q_INVOKABLE void cxxReloadMap();
    Q_INVOKABLE QString cxxGetConfig();
    Q_INVOKABLE bool cxxIsConfigValid();

signals:
    void urlChanged();
    void webServiceKeyChanged();
    void mapClicked(double lng, double lat);
    void markerClicked(const QString &title);
    void mapDblClicked(double lng, double lat);
    void geocodeResult(double lng, double lat, const QString &name, int which);
    void mouseMoved(double lng, double lat);
    void placeSearchResult(const QVariantList &results);
    void placeSearchError(const QString &message);
    void routeSearchResult(const QString &polylineJson, double distance, int duration);
    void routeSearchError(const QString &message);
    void weatherResult(const QString &city, const QString &weather, const QString &temperature);
    void weatherError(const QString &message);
    void annotationClicked(int index);
    void pageLoaded();
    void bridgeEvent(const QString &raw);

protected:
    void componentComplete() override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private slots:
    void updateBrowserBounds();
    void initializeBrowser();
    void pollBridge();

private:
    void loadConfig();
    static LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

    HWND m_hwnd = nullptr;
    HWND m_parentHwnd = nullptr;
    IWebBrowser2 *m_webBrowser = nullptr;
    IConnectionPoint *m_connPoint = nullptr;
    DWORD m_cookie = 0;

    QUrl m_url;
    bool m_initialized = false;
    QTimer *m_resizeTimer = nullptr;
    QTimer *m_bridgeTimer = nullptr;
    QNetworkAccessManager *m_nam = nullptr;
    QString m_amapKey;
    QString m_configJsKey;
    QString m_webServiceKey;

    struct ExternalDispatch : IDispatch {
        WebView2Item *self;
        ULONG refCount = 1;
        ExternalDispatch(WebView2Item *s) : self(s) {}
        HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv);
        ULONG STDMETHODCALLTYPE AddRef() { return ++refCount; }
        ULONG STDMETHODCALLTYPE Release();
        HRESULT STDMETHODCALLTYPE GetTypeInfoCount(UINT *) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetTypeInfo(UINT, LCID, ITypeInfo **) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetIDsOfNames(REFIID, LPOLESTR *, UINT, LCID, DISPID *);
        HRESULT STDMETHODCALLTYPE Invoke(DISPID, REFIID, LCID, WORD, DISPPARAMS *, VARIANT *, EXCEPINFO *, UINT *);
    };
    struct BrowserEventSink : IDispatch {
        WebView2Item *self;
        ULONG refCount = 1;
        BrowserEventSink(WebView2Item *s) : self(s) {}
        HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv);
        ULONG STDMETHODCALLTYPE AddRef() { return ++refCount; }
        ULONG STDMETHODCALLTYPE Release();
        HRESULT STDMETHODCALLTYPE GetTypeInfoCount(UINT *) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetTypeInfo(UINT, LCID, ITypeInfo **) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetIDsOfNames(REFIID, LPOLESTR *, UINT, LCID, DISPID *) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE Invoke(DISPID, REFIID, LCID, WORD, DISPPARAMS *, VARIANT *, EXCEPINFO *, UINT *);
    };

    struct InPlaceFrame : IOleInPlaceFrame {
        WebView2Item *self = nullptr;
        ULONG refCount = 1;
        HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv);
        ULONG STDMETHODCALLTYPE AddRef() { return ++refCount; }
        ULONG STDMETHODCALLTYPE Release();
        HRESULT STDMETHODCALLTYPE GetWindow(HWND *phwnd);
        HRESULT STDMETHODCALLTYPE ContextSensitiveHelp(BOOL) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetBorder(LPRECT) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE RequestBorderSpace(LPCRECT) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE SetBorderSpace(LPCRECT) { return S_OK; }
        HRESULT STDMETHODCALLTYPE SetActiveObject(IOleInPlaceActiveObject *, LPCOLESTR) { return S_OK; }
        HRESULT STDMETHODCALLTYPE InsertMenus(HMENU, LPOLEMENUGROUPWIDTHS) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE SetMenu(HMENU, HOLEMENU, HWND) { return S_OK; }
        HRESULT STDMETHODCALLTYPE RemoveMenus(HMENU) { return S_OK; }
        HRESULT STDMETHODCALLTYPE SetStatusText(LPCWSTR) { return S_OK; }
        HRESULT STDMETHODCALLTYPE EnableModeless(BOOL) { return S_OK; }
        HRESULT STDMETHODCALLTYPE TranslateAccelerator(LPMSG, WORD) { return E_NOTIMPL; }
    };

    struct ClientSite : IOleClientSite, IOleInPlaceSite, IDocHostUIHandler, IServiceProvider {
        WebView2Item *self;
        InPlaceFrame frame;
        ULONG refCount = 1;
        ClientSite(WebView2Item *s) : self(s) { frame.self = s; }
        HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv);
        ULONG STDMETHODCALLTYPE AddRef() { return ++refCount; }
        ULONG STDMETHODCALLTYPE Release();

        // IOleClientSite
        HRESULT STDMETHODCALLTYPE SaveObject() { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetMoniker(DWORD, DWORD, IMoniker **) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetContainer(IOleContainer **ppContainer);
        HRESULT STDMETHODCALLTYPE ShowObject() { return S_OK; }
        HRESULT STDMETHODCALLTYPE OnShowWindow(BOOL) { return S_OK; }
        HRESULT STDMETHODCALLTYPE RequestNewObjectLayout() { return E_NOTIMPL; }

        HRESULT STDMETHODCALLTYPE GetWindow(HWND *phwnd);
        HRESULT STDMETHODCALLTYPE ContextSensitiveHelp(BOOL) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE CanInPlaceActivate() { return S_OK; }
        HRESULT STDMETHODCALLTYPE OnInPlaceActivate() { return S_OK; }
        HRESULT STDMETHODCALLTYPE OnUIActivate() { return S_OK; }
        HRESULT STDMETHODCALLTYPE GetWindowContext(IOleInPlaceFrame **, IOleInPlaceUIWindow **, LPRECT, LPRECT, LPOLEINPLACEFRAMEINFO);
        HRESULT STDMETHODCALLTYPE Scroll(SIZE) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE OnUIDeactivate(BOOL) { return S_OK; }
        HRESULT STDMETHODCALLTYPE OnInPlaceDeactivate() { return S_OK; }
        HRESULT STDMETHODCALLTYPE DiscardUndoState() { return S_OK; }
        HRESULT STDMETHODCALLTYPE DeactivateAndUndo() { return S_OK; }
        HRESULT STDMETHODCALLTYPE OnPosRectChange(LPCRECT)
        HRESULT STDMETHODCALLTYPE ShowContextMenu(DWORD, POINT *, IUnknown *, IDispatch *) { return S_OK; }
        HRESULT STDMETHODCALLTYPE GetHostInfo(DOCHOSTUIINFO *pInfo);
        HRESULT STDMETHODCALLTYPE ShowUI(DWORD, IOleInPlaceActiveObject *, IOleCommandTarget *, IOleInPlaceFrame *, IOleInPlaceUIWindow *) { return S_OK; }
        HRESULT STDMETHODCALLTYPE HideUI() { return S_OK; }
        HRESULT STDMETHODCALLTYPE UpdateUI() { return S_OK; }
        HRESULT STDMETHODCALLTYPE EnableModeless(BOOL) { return S_OK; }
        HRESULT STDMETHODCALLTYPE OnDocWindowActivate(BOOL) { return S_OK; }
        HRESULT STDMETHODCALLTYPE OnFrameWindowActivate(BOOL) { return S_OK; }
        HRESULT STDMETHODCALLTYPE ResizeBorder(LPCRECT, IOleInPlaceUIWindow *, BOOL) { return S_OK; }
        HRESULT STDMETHODCALLTYPE TranslateAccelerator(LPMSG, const GUID *, DWORD) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetOptionKeyPath(LPOLESTR *, DWORD) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetDropTarget(IDropTarget *, IDropTarget **) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetExternal(IDispatch **ppDispatch);
        HRESULT STDMETHODCALLTYPE TranslateUrl(DWORD, LPWSTR, LPWSTR *) { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE FilterDataObject(IDataObject *, IDataObject **) { return E_NOTIMPL; }

        HRESULT STDMETHODCALLTYPE QueryService(REFGUID guidService, REFIID riid, void **ppvObject);
    };

    ClientSite *m_clientSite = nullptr;
    ExternalDispatch *m_external = nullptr;
    BrowserEventSink *m_eventSink = nullptr;
};
