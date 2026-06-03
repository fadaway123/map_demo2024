import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import map_demo2024

ApplicationWindow {
    width: 1800
    height: 1200
    visible: true
    title: "LIUNIAN的个人化地图"

    readonly property double earthRadius: 6371
    readonly property double px: 1.5
    property bool autoCalc: true
    property bool readyCalc: false
    property string pendingText: ""
    property int pendingWhich: 0
    property bool searchPanelVisible: false
    property var searchResults: []
    property int searchStep: 0
    property bool searchResultPending: false
    property var searchPoints: []
    property bool navMode: false
    property int weatherPendingWhich: -1
    property int mapMode: 0
    property var annotations: []
    property double pendingAnnotateLng: 0
    property double pendingAnnotateLat: 0
    property bool annotPanelVisible: false
    property int editIndex: -1
    property string filterTag: ""
    property string pathFilterTag: ""
    property var uniqueTags: []
    property string pendingImageData: ""
    property string pendingImageFile: ""
    property bool regeoMode: false
    property var currentPath: []
    property var savedPaths: []
    property var _pathModel: []
    property var eventLog: [0]
    property string annotPanelTab: "标注"
    property int pathEditIdx: -1
    property string pathEditCurImgData: ""
    property string pathEditCurImgFile: ""
    property var knownTags: []
    onSavedPathsChanged: updatePathModel()
    onPathFilterTagChanged: updatePathModel()

    readonly property var cityCoords: ({
        '北京': [116.407428, 39.90423], '上海': [121.473701, 31.230416],
        '广州': [113.264434, 23.129162], '深圳': [114.057868, 22.543099],
        '武汉': [114.305392, 30.5928],   '成都': [104.066541, 30.572269],
        '杭州': [120.15507, 30.274085],  '南京': [118.796877, 32.060255],
        '重庆': [106.551556, 29.563009], '西安': [108.940174, 34.341568],
        '长沙': [112.938814, 28.228209], '青岛': [120.382639, 36.067082],
        '大连': [121.614682, 38.913585], '厦门': [118.089425, 24.479833],
        '苏州': [120.583191, 31.298974], '天津': [117.191008, 39.143607],
        '郑州': [113.625368, 34.7466],   '沈阳': [123.431474, 41.805698],
        '昆明': [102.834544, 24.88095],  '南宁': [108.366543, 22.817109],
        '哈尔滨': [126.534967, 45.803775], '合肥': [117.229082, 31.820829],
        '福州': [119.296473, 26.074211], '贵阳': [106.630236, 26.64702],
        '海口': [110.19822, 20.04441],   '兰州': [103.834303, 36.061089],
        '南昌': [115.593671, 28.673474], '太原': [112.548879, 37.87059],
        '济南': [117.001112, 36.651934], '长春': [125.32601, 43.901707],
        '拉萨': [91.082484, 29.644576],  '乌鲁木齐': [87.616848, 43.793026]
    })

    QtObject {
        id: pointA
        property double lng: 0
        property double lat: 0
        property bool set: false
        property string name: ""
    }

    QtObject {
        id: pointB
        property double lng: 0
        property double lat: 0
        property bool set: false
        property string name: ""
    }

    Timer {
        id: geoTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (pendingText.length > 1)
                webView.cxxGeocode(pendingText, pendingWhich)
            pendingText = ""
        }
    }

    function haversine(lng1, lat1, lng2, lat2) {
        var dLat = (lat2 - lat1) * Math.PI / 180
        var dLng = (lng2 - lng1) * Math.PI / 180
        var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                Math.sin(dLng / 2) * Math.sin(dLng / 2)
        return earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    }

    function updateReadyCalc() {
        readyCalc = pointA.lng !== 0 && pointA.lat !== 0 && pointB.lng !== 0 && pointB.lat !== 0
    }

    function tryCalcDist() {
        if (autoCalc && readyCalc) updateDistance()
    }

    function weatherToEffect(weather) {
        var w = weather || ''
        if (w.indexOf('雷') >= 0) return 'thunderstorm'
        if (w.indexOf('雪') >= 0) return 'snow'
        if (w.indexOf('雨') >= 0) return 'rain'
        if (w.indexOf('雾') >= 0 || w.indexOf('霾') >= 0) return 'fog'
        if (w.indexOf('多云') >= 0) return 'cloudy'
        if (w.indexOf('阴') >= 0) return 'overcast'
        return 'sunny'
    }

    function reverseLookup(lng, lat) {
        var minDist = Infinity
        var nearest = ""
        for (var name in cityCoords) {
            var dx = cityCoords[name][0] - lng
            var dy = cityCoords[name][1] - lat
            var dist = dx * dx + dy * dy
            if (dist < minDist) {
                minDist = dist
                nearest = name
            }
        }
        return nearest
    }

    function refreshMap() {
        webView.executeScript("clearSmallMarkers(); clearLines();")
        if (pointA.lng !== 0 && pointA.lat !== 0)
            webView.executeScript("addSmallMarker(" + pointA.lng + ", " + pointA.lat + ", 'blue');")
        if (pointB.lng !== 0 && pointB.lat !== 0)
            webView.executeScript("addSmallMarker(" + pointB.lng + ", " + pointB.lat + ", 'red');")
        if (readyCalc) {
            webView.executeScript("drawGreenPath([[" + pointA.lng + "," + pointA.lat + "],[" + pointB.lng + "," + pointB.lat + "]]);")
            webView.executeScript("map.setFitView();")
        }
    }

    function updateDistance() {
        if (readyCalc) {
            var d = haversine(pointA.lng, pointA.lat, pointB.lng, pointB.lat)
            distanceField.text = (d >= 1 ? d.toFixed(2) + " 公里" : (d * 1000).toFixed(0) + " 米")
        } else {
            distanceField.text = ""
        }
    }

    function markFromPosition(lng, lat) {
        if (pointA.lng === 0 && pointA.lat === 0) {
            pointA.lng = lng; pointA.lat = lat; pointA.set = true
            pointA.name = reverseLookup(lng, lat)
            nameA_field.text = pointA.name
            lngA_field.text = lng.toFixed(6)
            latA_field.text = lat.toFixed(6)
            webView.cxxReGeocode(lng, lat, 0)
        } else {
            pointB.lng = lng; pointB.lat = lat; pointB.set = true
            pointB.name = reverseLookup(lng, lat)
            nameB_field.text = pointB.name
            lngB_field.text = lng.toFixed(6)
            latB_field.text = lat.toFixed(6)
            webView.cxxReGeocode(lng, lat, 1)
        }
        updateReadyCalc()
        if (readyCalc) tryCalcDist()
    }

    function applyResult(lng, lat, name, which) {
        var fromSearch = searchResultPending
        searchResultPending = false
        if (fromSearch) {
            searchPoints.push([lng, lat])
            webView.executeScript("addSearchMarker(" + lng + ", " + lat + ");")
            if (searchPoints.length >= 2) {
                var jsPath = "["
                for (var i = 0; i < searchPoints.length; i++) {
                    if (i > 0) jsPath += ", "
                    jsPath += "[" + searchPoints[i][0] + ", " + searchPoints[i][1] + "]"
                }
                jsPath += "]"
                webView.executeScript("drawBlackPath(" + jsPath + ");")
                var total = 0
                for (i = 1; i < searchPoints.length; i++) {
                    total += haversine(searchPoints[i-1][0], searchPoints[i-1][1], searchPoints[i][0], searchPoints[i][1])
                }
                distanceField.text = (total >= 1 ? total.toFixed(2) + " 公里" : (total * 1000).toFixed(0) + " 米")
                    + " (搜索路径)"
            }
        }
        if (!fromSearch) {
            searchPoints.push([lng, lat])
            webView.executeScript("addSearchMarker(" + lng + ", " + lat + ");")
            if (searchPoints.length >= 2) {
                var jsPath2 = "["
                for (var j = 0; j < searchPoints.length; j++) {
                    if (j > 0) jsPath2 += ", "
                    jsPath2 += "[" + searchPoints[j][0] + ", " + searchPoints[j][1] + "]"
                }
                jsPath2 += "]"
                webView.executeScript("drawBlackPath(" + jsPath2 + ");")
                var total2 = 0
                for (j = 1; j < searchPoints.length; j++) {
                    total2 += haversine(searchPoints[j-1][0], searchPoints[j-1][1], searchPoints[j][0], searchPoints[j][1])
                }
                distanceField.text = (total2 >= 1 ? total2.toFixed(2) + " 公里" : (total2 * 1000).toFixed(0) + " 米")
                    + " (已标注路径)"
            }
        }
        var pt = which === 0 ? pointA : pointB
        pt.lng = lng; pt.lat = lat; pt.set = true; pt.name = name
        if (which === 0) {
            nameA_field.text = name
            lngA_field.text = lng.toFixed(6)
            latA_field.text = lat.toFixed(6)
        } else {
            nameB_field.text = name
            lngB_field.text = lng.toFixed(6)
            latB_field.text = lat.toFixed(6)
        }
            if (mapMode !== 1 && !fromSearch) {
                refreshMap()
                if (!navMode) tryCalcDist()
            }
            if (!fromSearch) {
                weatherPendingWhich = which
                webView.cxxWeather(reverseLookup(lng, lat))
            }
    }

    function clearAll() {
        pointA.lng = 0; pointA.lat = 0; pointA.set = false; pointA.name = ""
        pointB.lng = 0; pointB.lat = 0; pointB.set = false; pointB.name = ""
        nameA_field.text = ""; lngA_field.text = ""; latA_field.text = ""
        nameB_field.text = ""; lngB_field.text = ""; latB_field.text = ""
        distanceField.text = ""
        weatherA.text = ""; weatherB.text = ""; weatherPendingWhich = -1
        readyCalc = false
        pendingText = ""
        geoTimer.stop()
        searchStep = 0; searchResultPending = false; searchPoints = []
        navMode = false
        annotPanelVisible = false
        mapMode = 0; currentPath = []; savedPaths = []; annotations = []; uniqueTags = []
        webView.executeScript("clearMarkers(); clearSmallMarkers(); clearLines(); clearSearch(); clearNav(); clearAnnotations(); clearSavedPathMarkers(); setMapDragEnabled(true);")
        webView.executeScript("setWeatherEffect('none')")
        saveAnnotationsGrouped()
        webView.executeScript("document.getElementById('__evt').innerText='sys:clearAll'")
    }

    function setMapInteraction(enabled) {
        if (!enabled)
            webView.releaseBrowserFocus()
    }

    function onEnterPressed() {
        if (!autoCalc) {
            updateDistance()
        }
    }

    function deleteAnnotation(idx) {
        annotations.splice(idx, 1)
        annotations = annotations.concat()
        collectUniqueTags()
        refreshAnnotationMarkers()
        saveAnnotationsGrouped()
        webView.executeScript("document.getElementById('__evt').innerText='sys:delAnnot:" + idx + "'")
    }

    function setAnnotationAsPoint(which, obj) {
        var pt = which === 0 ? pointA : pointB
        pt.lng = obj.lng
        pt.lat = obj.lat
        pt.set = true
        pt.name = obj.title || reverseLookup(obj.lng, obj.lat)
        if (which === 0) {
            nameA_field.text = pt.name
            lngA_field.text = obj.lng.toFixed(6)
            latA_field.text = obj.lat.toFixed(6)
        } else {
            nameB_field.text = pt.name
            lngB_field.text = obj.lng.toFixed(6)
            latB_field.text = obj.lat.toFixed(6)
        }
        updateReadyCalc()
        refreshMap()
        if (!navMode) tryCalcDist()
    }

    function togglePathMode(enabled) {
        if (enabled) {
            mapMode = 2
            webView.executeScript("clearAnnotations();")
            drawSavedPathsOnMap()
        } else {
            mapMode = 0
            webView.executeScript("setMapDragEnabled(true);")
            refreshAnnotationMarkers()
            drawSavedPathsOnMap()
        }
    }

    function addPathPoint(lng, lat) {
        currentPath.push({lng: lng, lat: lat})
    }

    function finishPath() {
        if (currentPath.length < 2) return
        pathTitleField.text = ""
        pathTagField.text = "TEMP"
        pathDialog.open()
    }

    function cancelPath() {
        currentPath = []
        pathTimeField.text = ""
        togglePathMode(false)
    }

    function savePathFromDialog() {
        if (currentPath.length < 2) return
        var pts = []
        for (var i = 0; i < currentPath.length; i++)
            pts.push([currentPath[i].lng, currentPath[i].lat])
        var totalDist = 0
        for (var i = 1; i < pts.length; i++)
            totalDist += haversine(pts[i-1][0], pts[i-1][1], pts[i][0], pts[i][1])
        var tag = pathTagField.text.trim() || "TEMP"
        var obj = {
            id: Date.now().toString() + Math.random().toString(36).substr(2, 9),
            title: pathTitleField.text,
            points: pts,
            tag: tag,
            distance: totalDist,
            distText: totalDist >= 1 ? totalDist.toFixed(2) + " 公里" : (totalDist * 1000).toFixed(0) + " 米",
            customTime: pathTimeField.text,
            thumbData: "",
            imageFile: "",
            note: "",
            time: new Date().toISOString()
        }
        savedPaths.push(obj)
        savedPaths = savedPaths.concat()
        currentPath = []
        collectUniqueTags()
        saveAnnotationsGrouped()
        drawSavedPathsOnMap()
        togglePathMode(false)
        pathTitleField.text = ""
        pathTimeField.text = ""
    }

    function updatePathModel() {
        if (pathFilterTag === "") {
            _pathModel = savedPaths.slice()
        } else {
            var filtered = []
            for (var i = 0; i < savedPaths.length; i++)
                if (savedPaths[i].tag === pathFilterTag)
                    filtered.push(savedPaths[i])
            _pathModel = filtered
        }
    }

    function deletePath(idx) {
        savedPaths.splice(idx, 1)
        savedPaths = savedPaths.concat()
        collectUniqueTags()
        saveAnnotationsGrouped()
        drawSavedPathsOnMap()
        webView.executeScript("document.getElementById('__evt').innerText='sys:delPath:" + idx + "'")
    }

    function editPath(idx) {
        pathEditIdx = idx
        var p = savedPaths[idx]
        pathEditTitleField.text = p.title || ""
        pathEditTagField.text = p.tag || ""
        pathEditTimeField.text = p.customTime || ""
        pathEditNoteField.text = p.note || ""
        pathEditCurImgData = p.thumbData || ""
        pathEditCurImgFile = p.imageFile || ""
        if (pathEditCurImgFile) {
            pathEditPreview.source = "file:///" + webView.cxxImageFullPath(pathEditCurImgFile)
            pathEditPreview.visible = true
        } else if (pathEditCurImgData) {
            pathEditPreview.source = pathEditCurImgData
            pathEditPreview.visible = true
        } else {
            pathEditPreview.source = ""
            pathEditPreview.visible = false
        }
        pathEditDialog.open()
    }

    function updatePathFromEdit() {
        var p = savedPaths[pathEditIdx]
        if (!p) return
        p.title = pathEditTitleField.text
        p.tag = pathEditTagField.text.trim() || "TEMP"
        p.customTime = pathEditTimeField.text
        p.note = pathEditNoteField.text
        p.thumbData = pathEditCurImgData
        p.imageFile = pathEditCurImgFile
        savedPaths = savedPaths.concat()
        collectUniqueTags()
        saveAnnotationsGrouped()
        drawSavedPathsOnMap()
    }

    function drawSavedPathsOnMap() {
        webView.executeScript("clearSavedPathMarkers();")
        for (var i = 0; i < savedPaths.length; i++) {
            var p = savedPaths[i]
            if (!p.points || p.points.length < 2) continue
            var flat = "["
            for (var j = 0; j < p.points.length; j++) {
                if (j > 0) flat += ","
                flat += p.points[j][0] + "," + p.points[j][1]
            }
            flat += "]"
            webView.executeScript("addPathDots(" + flat + ");")
            webView.executeScript("addPathPolyline(" + flat + ");")
        }
        webView.executeScript("reportPathMarkerCount();")
        webView.executeScript("setAnnotationLabelsVisible(" + (mapMode === 1) + ");")
    }

    function escapeJS(s) {
        return (s || "").replace(/\\/g,"\\\\").replace(/'/g,"\\'").replace(/\n/g,"\\n").replace(/\r/g,"\\r")
    }

    function refreshAnnotationMarkers() {
        webView.executeScript("clearAnnotations();")
        for (var i = 0; i < annotations.length; i++) {
            var a = annotations[i]
            webView.executeScript("addAnnotationMarker(" + a.lng + "," + a.lat + ",'" + escapeJS(a.title) + "','" + escapeJS(a.note) + "');")
        }
        webView.executeScript("setAnnotationLabelsVisible(" + (mapMode === 1) + ");")
    }

    function collectUniqueTags() {
        var result = []
        for (var i = 0; i < annotations.length; i++) {
            var t = annotations[i].tag || ""
            if (t && result.indexOf(t) < 0) result.push(t)
        }
        for (var i = 0; i < savedPaths.length; i++) {
            var t = savedPaths[i].tag || ""
            if (t && result.indexOf(t) < 0) result.push(t)
        }
        uniqueTags = result
    }

    function saveAnnotationsGrouped() {
        var grouped = {}
        for (var i = 0; i < annotations.length; i++) {
            var a = annotations[i]
            var tag = a.tag || ""
            if (!grouped[tag]) grouped[tag] = []
            grouped[tag].push(a)
            if (tag && knownTags.indexOf(tag) < 0) knownTags.push(tag)
        }
        for (var i = 0; i < knownTags.length; i++) {
            if (!grouped[knownTags[i]]) grouped[knownTags[i]] = []
        }
        if (!grouped[""]) grouped[""] = []
        grouped["_paths"] = savedPaths.slice()
        webView.cxxSaveAnnotations(JSON.stringify(grouped))
    }

    function loadAnnotationsFromGrouped(jsonStr) {
        console.log("loadAnnotationsFromGrouped: input length=" + jsonStr.length)
        var parsed = JSON.parse(jsonStr)
        console.log("loadAnnotationsFromGrouped: isArray=" + Array.isArray(parsed) + " has_paths=" + ("_paths" in parsed))
        if (Array.isArray(parsed)) {
            annotations = parsed
            savedPaths = []
            knownTags = []
            for (var i = 0; i < annotations.length; i++) {
                var t = annotations[i].tag || ""
                if (t && knownTags.indexOf(t) < 0) knownTags.push(t)
                if (!annotations[i].id) annotations[i].id = Date.now().toString() + Math.random().toString(36).substr(2, 9)
            }
        } else {
            knownTags = []
            for (var key in parsed) {
                if (key !== "_tags" && key !== "_paths") knownTags.push(key)
            }
            var result = []
            savedPaths = parsed["_paths"] || []
            console.log("loadAnnotationsFromGrouped: loaded " + savedPaths.length + " paths")
            for (var i = 0; i < savedPaths.length; i++) {
                if (!savedPaths[i].id) savedPaths[i].id = Date.now().toString() + Math.random().toString(36).substr(2, 9)
            }
            delete parsed["_tags"]
            delete parsed["_paths"]
            for (var tag in parsed) {
                var items = parsed[tag]
                for (var i = 0; i < items.length; i++) {
                    items[i].tag = items[i].tag || tag
                    if (!items[i].id) items[i].id = Date.now().toString() + Math.random().toString(36).substr(2, 9)
                    result.push(items[i])
                }
            }
            annotations = result
        }
        console.log("loadAnnotationsFromGrouped: final annotations=" + annotations.length + " paths=" + savedPaths.length)
        collectUniqueTags()
        saveAnnotationsGrouped()
    }

    Item {
        id: keyHandler
        focus: true
        Keys.onReturnPressed: onEnterPressed()
        Keys.onEnterPressed: onEnterPressed()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 9
            spacing: 9

            Button { text: "添加测试标记"; onClicked: webView.executeScript("addMarker(114.305392, 30.5928, '武汉');") }
            Button { text: "绘制轨迹"; onClicked: webView.executeScript("drawGreenPath([[114.305392, 30.5928], [114.315392, 30.6028], [114.325392, 30.5928]]);") }
            Button { text: "使用准备"; onClicked: setupDialog.open() }

            Item { Layout.fillWidth: true }

            Label { text: "自动计算:"; font.bold: true }
            Switch {
                id: autoSwitch
                checked: autoCalc
                onCheckedChanged: autoCalc = checked
            }

            Button {
                text: annotPanelVisible ? "关闭标注" : "标注管理"
                highlighted: annotPanelVisible
                onClicked: annotPanelVisible = !annotPanelVisible
            }
            Button {
                text: searchPanelVisible ? "关闭搜索" : "地点搜索"
                onClicked: searchPanelVisible = !searchPanelVisible
            }
            Button {
                text: navMode ? "关闭导航" : "导航"
                onClicked: {
                    navMode = !navMode
                    if (navMode) {
                        if (readyCalc) {
                            console.log("导航: 调用 cxxRouteSearch", pointA.lng, pointA.lat, pointB.lng, pointB.lat)
                            webView.cxxRouteSearch(pointA.lng, pointA.lat, pointB.lng, pointB.lat)
                        } else {
                            console.log("导航失败: readyCalc=false, 请先标记 A/B 点")
                            distanceField.text = "请先标记起点和终点再导航"
                            navMode = false
                        }
                    } else {
                        webView.executeScript("clearNav();")
                        tryCalcDist()
                    }
                }
            }
            Button { text: "清除所有"; onClicked: clearConfirmDialog.open() }
            Button { text: "事件"; onClicked: eventLogDialog.open() }
        }

        GridLayout {
            columns: 9
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            rowSpacing: 6

            Label { text: "起点 A:"; font.bold: true }
            Label { text: "名称"; font.pixelSize: 16; color: "gray"; Layout.fillWidth: true }
            TextField {
                id: nameA_field
                Layout.preferredWidth: 80
                placeholderText: "输入地名"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
                Keys.onReturnPressed: onEnterPressed()
                Keys.onEnterPressed: onEnterPressed()
                onTextChanged: {
                    if (text.length > 1 && text !== pointA.name) {
                        pendingText = text; pendingWhich = 0; geoTimer.restart()
                    }
                }
            }
            Label { text: "经度"; font.pixelSize: 11; color: "gray"; Layout.fillWidth: true }
            TextField {
                id: lngA_field; Layout.fillWidth: true
                placeholderText: "经度"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
                Keys.onReturnPressed: onEnterPressed()
                Keys.onEnterPressed: onEnterPressed()
                onEditingFinished: {
                    var v = parseFloat(text)
                    if (!isNaN(v)) { pointA.lng = v; pointA.set = true; pointA.name = reverseLookup(v, pointA.lat); nameA_field.text = pointA.name; webView.cxxReGeocode(v, pointA.lat, 0); refreshMap(); updateReadyCalc(); if (readyCalc) tryCalcDist() }
                }
            }
            Label { text: "纬度"; font.pixelSize: 11; color: "gray"; Layout.fillWidth: true }
            TextField {
                id: latA_field; Layout.fillWidth: true
                placeholderText: "纬度"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
                Keys.onReturnPressed: onEnterPressed()
                Keys.onEnterPressed: onEnterPressed()
                onEditingFinished: {
                    var v = parseFloat(text)
                    if (!isNaN(v)) { pointA.lat = v; pointA.set = true; pointA.name = reverseLookup(pointA.lng, v); nameA_field.text = pointA.name; webView.cxxReGeocode(pointA.lng, v, 0); refreshMap(); updateReadyCalc(); if (readyCalc) tryCalcDist() }
                }
            }
            Label { id: weatherA; text: ""; font.pixelSize: 11; color: "#FF6F00"; Layout.fillWidth: true; Layout.columnSpan: 2; visible: text.length > 0 }

            Label { text: "终点 B:"; font.bold: true }
            Label { text: "名称"; font.pixelSize: 11; color: "gray"; Layout.fillWidth: true }
            TextField {
                id: nameB_field
                Layout.preferredWidth: 80
                placeholderText: "输入地名"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
                Keys.onReturnPressed: onEnterPressed()
                Keys.onEnterPressed: onEnterPressed()
                onTextChanged: {
                    if (text.length > 1 && text !== pointB.name) {
                        pendingText = text; pendingWhich = 1; geoTimer.restart()
                    }
                }
            }
            Label { text: "经度"; font.pixelSize: 11; color: "gray"; Layout.fillWidth: true }
            TextField {
                id: lngB_field; Layout.fillWidth: true
                placeholderText: "经度"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
                Keys.onReturnPressed: onEnterPressed()
                Keys.onEnterPressed: onEnterPressed()
                onEditingFinished: {
                    var v = parseFloat(text)
                    if (!isNaN(v)) { pointB.lng = v; pointB.set = true; pointB.name = reverseLookup(v, pointB.lat); nameB_field.text = pointB.name; webView.cxxReGeocode(v, pointB.lat, 1); refreshMap(); updateReadyCalc(); if (readyCalc) tryCalcDist() }
                }
            }
            Label { text: "纬度"; font.pixelSize: 11; color: "gray"; Layout.fillWidth: true }
            TextField {
                id: latB_field; Layout.fillWidth: true
                placeholderText: "纬度"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
                Keys.onReturnPressed: onEnterPressed()
                Keys.onEnterPressed: onEnterPressed()
                onEditingFinished: {
                    var v = parseFloat(text)
                    if (!isNaN(v)) { pointB.lat = v; pointB.set = true; pointB.name = reverseLookup(pointB.lng, v); nameB_field.text = pointB.name; webView.cxxReGeocode(pointB.lng, v, 1); refreshMap(); updateReadyCalc(); if (readyCalc) tryCalcDist() }
                }
            }
            Label { id: weatherB; text: ""; font.pixelSize: 11; color: "#FF6F00"; Layout.fillWidth: true; Layout.columnSpan: 2; visible: text.length > 0 }

        Label { text: webView.debugLoadMsg + " | paths=" + savedPaths.length + " model=" + _pathModel.length; font.pixelSize: 9; color: "red"; Layout.columnSpan: 9 }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            Layout.bottomMargin: 2
            spacing: 6

            Label { text: "距离:"; font.bold: true; font.pixelSize: 16 }

            TextField {
                id: distanceField
                Layout.fillWidth: true
                readOnly: true
                placeholderText: autoCalc ? "标记两点后自动计算" : "按 Enter 计算距离"
                font.pixelSize: 16
                font.bold: true
                color: "#2196F3"
                background: Rectangle {
                    color: "#F5F5F5"
                    border.color: "#E0E0E0"
                    border.width: 1
                    radius: 4
                }
            }

            TextField {
                id: searchInput
                visible: searchPanelVisible
                Layout.preferredWidth: 180
                placeholderText: "输入关键词"
                onAccepted: webView.cxxPlaceSearch(text)
            }
            Button {
                text: "搜索"
                visible: searchPanelVisible
                implicitWidth: 48
                onClicked: webView.cxxPlaceSearch(searchInput.text)
            }
        }

        Label {
            id: searchErrorLabel
            visible: searchPanelVisible && text.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            color: "red"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Rectangle {
            visible: searchPanelVisible
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            color: "white"
            border.color: "#DDD"
            border.width: 1
            radius: 3
            clip: true

            ListView {
                anchors.fill: parent
                anchors.margins: 2
                model: searchResults
                delegate: searchResultDelegate
                spacing: 2
                ScrollBar.vertical: ScrollBar { }
            }
        }

        Rectangle {
            visible: annotPanelVisible
            Layout.fillWidth: true
            Layout.preferredHeight: 260
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            color: "white"
            border.color: "#DDD"
            border.width: 1
            radius: 3
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: annotPanelTab === "标注"
                            ? "已保存标注 (" + annotations.length + ")"
                            : "已保存路径 (" + savedPaths.length + ")"
                        font.bold: true
                        font.pixelSize: 13
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "标注模式:"
                        font.pixelSize: 11; color: "gray"
                        visible: annotPanelTab === "标注" && mapMode !== 2
                    }
                    Switch {
                        visible: annotPanelTab === "标注" && mapMode !== 2
                        checked: mapMode === 1
                        onCheckedChanged: {
                            if (checked) {
                                mapMode = 1
                                webView.executeScript("setAnnotationLabelsVisible(true);")
                                webView.executeScript("clearSavedPathMarkers();")
                            } else {
                                mapMode = 0
                                webView.executeScript("setAnnotationLabelsVisible(false);")
                                webView.executeScript("setMapDragEnabled(true);")
                                drawSavedPathsOnMap()
                            }
                        }
                    }
                    Label { text: "位置查询:"; font.pixelSize: 11; color: "gray" }
                    Switch {
                        checked: regeoMode
                        onCheckedChanged: {
                            regeoMode = checked
                            webView.executeScript("setRegeoMode(" + regeoMode + ");")
                        }
                    }
                    Label { text: "路径模式:"; font.pixelSize: 11; color: "gray" }
                    Switch {
                        checked: mapMode === 2
                        onCheckedChanged: togglePathMode(checked)
                    }
                    Button {
                        text: "完成"; visible: mapMode === 2
                        implicitWidth: 40; implicitHeight: 24
                        onClicked: finishPath()
                    }
                    Button {
                        text: "取消"; visible: mapMode === 2
                        implicitWidth: 40; implicitHeight: 24
                        onClicked: cancelPath()
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    Button {
                        text: "全部"
                        highlighted: annotPanelTab === "标注" ? filterTag === "" : pathFilterTag === ""
                        implicitHeight: 24
                        onClicked: {
                            if (annotPanelTab === "标注") filterTag = ""
                            else pathFilterTag = ""
                        }
                    }
                    Repeater {
                        model: uniqueTags
                        delegate: Button {
                            text: modelData
                            highlighted: annotPanelTab === "标注" ? filterTag === modelData : pathFilterTag === modelData
                            implicitHeight: 24
                            onClicked: {
                                if (annotPanelTab === "标注") filterTag = (filterTag === modelData ? "" : modelData)
                                else pathFilterTag = (pathFilterTag === modelData ? "" : modelData)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Button {
                        text: "清理标签"
                        implicitWidth: 72
                        onClicked: { collectUniqueTags(); saveAnnotationsGrouped() }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Button {
                        text: "标注"
                        highlighted: annotPanelTab === "标注"
                        implicitHeight: 22; Layout.fillWidth: true
                        onClicked: annotPanelTab = "标注"
                    }
                    Button {
                        text: "路径"
                        highlighted: annotPanelTab === "路径"
                        implicitHeight: 22; Layout.fillWidth: true
                        onClicked: annotPanelTab = "路径"
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: annotListView
                        visible: annotPanelTab === "标注"
                        anchors.fill: parent
                        model: {
                            if (filterTag === "") return annotations
                            var filtered = []
                            for (var i = 0; i < annotations.length; i++) {
                                if (annotations[i].tag === filterTag)
                                    filtered.push(annotations[i])
                            }
                            return filtered
                        }
                        spacing: 2
                        ScrollBar.vertical: ScrollBar { }

                        delegate: Rectangle {
                            width: annotListView.width
                            height: 56
                            color: mouseArea.containsMouse ? "#FFF3E0" : "transparent"
                            radius: 3
                            border.color: "#E0E0E0"
                            border.width: 1

                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    webView.executeScript("flyTo(" + modelData.lng + "," + modelData.lat + ");")
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 6

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Label {
                                        text: modelData.title || "(未命名)"
                                        font.bold: true
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: {
                                            var s = modelData.lng.toFixed(4) + ", " + modelData.lat.toFixed(4)
                                            if (modelData.thumbData) s = "[图] " + s
                                            if (modelData.note) s = modelData.note + " · " + s
                                            if (modelData.tag) s = "[" + modelData.tag + "] " + s
                                            return s
                                        }
                                        font.pixelSize: 10
                                        color: "gray"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Button {
                                    text: "编辑"
                                    implicitWidth: 48
                                    implicitHeight: 26
                                    onClicked: {
                                        var found = -1
                                        for (var i = 0; i < annotations.length; i++) {
                                            if (annotations[i].id === modelData.id) { found = i; break }
                                        }
                                        if (found < 0) return
                                        editIndex = found
                                        pendingAnnotateLng = modelData.lng
                                        pendingAnnotateLat = modelData.lat
                                        titleField.text = modelData.title || ""
                                        noteField.text = modelData.note || ""
                                        tagField.text = modelData.tag || ""
                                        pendingImageData = modelData.thumbData || ""
                                        pendingImageFile = modelData.imageFile || ""
                                        if (pendingImageFile) {
                                            imagePreview.source = "file:///" + webView.cxxImageFullPath(pendingImageFile)
                                            imagePreview.visible = true
                                        } else if (pendingImageData) {
                                            imagePreview.source = pendingImageData
                                            imagePreview.visible = true
                                        } else {
                                            imagePreview.source = ""
                                            imagePreview.visible = false
                                        }
                                        annotationDialog.title = "编辑标注"
                                        annotationDialog.open()
                                    }
                                }

                                Button {
                                    text: "图文"
                                    implicitWidth: 48
                                    implicitHeight: 26
                                    visible: modelData.thumbData || modelData.imageFile ? true : false
                                    onClicked: {
                                        var src = ""
                                        if (modelData.imageFile)
                                            src = "file:///" + webView.cxxImageFullPath(modelData.imageFile)
                                        else if (modelData.thumbData)
                                            src = modelData.thumbData
                                        annotPopupImg.source = src
                                        annotImgDialog.imgTitle = modelData.title || "(未命名)"
                                        annotImgDialog.imgNote = modelData.note || ""
                                        annotImgDialog.imgCoords = modelData.lng.toFixed(5) + ", " + modelData.lat.toFixed(5)
                                        annotImgDialog.open()
                                    }
                                }
                                Button {
                                    text: "A"
                                    implicitWidth: 32
                                    implicitHeight: 26
                                    highlighted: pointA.set && pointA.lng === modelData.lng && pointA.lat === modelData.lat
                                    onClicked: setAnnotationAsPoint(0, modelData)
                                }
                                Button {
                                    text: "B"
                                    implicitWidth: 32
                                    implicitHeight: 26
                                    highlighted: pointB.set && pointB.lng === modelData.lng && pointB.lat === modelData.lat
                                    onClicked: setAnnotationAsPoint(1, modelData)
                                }

                                Button {
                                    text: "删除"
                                    implicitWidth: 48
                                    implicitHeight: 26
                                    onClicked: {
                                        for (var i = 0; i < annotations.length; i++) {
                                            if (annotations[i].id === modelData.id) {
                                                deleteAnnotation(i); break
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ListView {
                        id: pathListView
                        visible: annotPanelTab === "路径"
                        anchors.fill: parent
                        model: _pathModel
                        spacing: 2
                        ScrollBar.vertical: ScrollBar { }

                        delegate: Rectangle {
                            width: pathListView.width
                            height: 56
                            color: mouseArea2.containsMouse ? "#F3E5F5" : "transparent"
                            radius: 3
                            border.color: "#E0E0E0"
                            border.width: 1

                            MouseArea {
                                id: mouseArea2
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (modelData.points && modelData.points.length > 0) {
                                        webView.executeScript("flyTo(" + modelData.points[0][0] + "," + modelData.points[0][1] + ");")
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 6

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Label {
                                        text: (modelData.title || "未命名路径") + " · " + (modelData.points ? modelData.points.length : 0) + " 个点"
                                        font.bold: true
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: {
                                            var s = modelData.tag ? "[" + modelData.tag + "] " : ""
                                            if (modelData.note) s += modelData.note + " · "
                                            if (modelData.distText) s += modelData.distText + " "
                                            if (modelData.customTime) s += "⏱ " + modelData.customTime + " "
                                            s += (modelData.time || "")
                                            return s
                                        }
                                        font.pixelSize: 10
                                        color: "gray"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Button {
                                    text: "编辑"
                                    implicitWidth: 48
                                    implicitHeight: 26
                                    onClicked: {
                                        for (var i = 0; i < savedPaths.length; i++) {
                                            if (savedPaths[i].id === modelData.id) {
                                                editPath(i); break
                                            }
                                        }
                                    }
                                }
                                Button {
                                    text: "图文"
                                    implicitWidth: 48
                                    implicitHeight: 26
                                    visible: modelData.thumbData || modelData.imageFile ? true : false
                                    onClicked: {
                                        var src = ""
                                        if (modelData.imageFile)
                                            src = "file:///" + webView.cxxImageFullPath(modelData.imageFile)
                                        else if (modelData.thumbData)
                                            src = modelData.thumbData
                                        pathPopupImg.source = src
                                        pathImgDialog.imgTitle = modelData.title || "未命名路径"
                                        pathImgDialog.imgNote = modelData.note || ""
                                        pathImgDialog.open()
                                    }
                                }
                                Button {
                                    text: "删除"
                                    implicitWidth: 48
                                    implicitHeight: 26
                                    onClicked: {
                                        for (var i = 0; i < savedPaths.length; i++) {
                                            if (savedPaths[i].id === modelData.id) {
                                                deletePath(i); break
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            WebView2 {
                id: webView
                anchors.fill: parent
                url: "qrc:/map.html"

                onMapClicked: {
                    if (mapMode === 2) {
                        addPathPoint(lng, lat)
                    } else {
                        console.log("单击地图:", lng.toFixed(6), lat.toFixed(6))
                    }
                    keyHandler.forceActiveFocus()
                }

                onMapDblClicked: {
                    if (mapMode === 1) {
                        pendingAnnotateLng = lng
                        pendingAnnotateLat = lat
                        webView.releaseBrowserFocus()
                        annotationDialog.open()
                    } else {
                        markFromPosition(lng, lat)
                    }
                }

                onGeocodeResult: {
                    applyResult(lng, lat, name, which)
                }

                onMarkerClicked: {
                    console.log("标记点击:", title)
                }

                onPlaceSearchResult: {
                    searchResults = results
                    searchErrorLabel.text = results.length > 0 ? "" : "无结果"
                    searchErrorLabel.color = results.length > 0 ? "transparent" : "gray"
                }

                onPlaceSearchError: {
                    searchErrorLabel.text = message
                    searchErrorLabel.color = "red"
                }

                onRouteSearchResult: {
                    console.log("导航成功, 坐标点数:", polylineJson.split("[").length - 1, "距离:", distance, "时长:", duration)
                    webView.executeScript("drawNavPath(" + polylineJson + ");")
                    var km = distance / 1000
                    var min = Math.round(duration / 60)
                    distanceField.text = km.toFixed(1) + " 公里 (约 " + min + " 分钟)"
                }

                onRouteSearchError: {
                    console.log("导航错误:", message)
                    distanceField.text = "导航失败: " + message
                    navMode = false
                }

                onWeatherResult: {
                    if (weatherPendingWhich === 0)
                        weatherA.text = weather + " " + temperature + "°C"
                    else if (weatherPendingWhich === 1)
                        weatherB.text = weather + " " + temperature + "°C"
                    webView.executeScript("setWeatherEffect('" + weatherToEffect(weather) + "')")
                    weatherPendingWhich = -1
                }

                onWeatherError: {
                    console.log("天气错误:", message)
                    weatherPendingWhich = -1
                }

                onAnnotationClicked: {
                    var a = annotations[index]
                    if (!a) return
                    var src = ""
                    if (a.imageFile)
                        src = "file:///" + webView.cxxImageFullPath(a.imageFile)
                    else
                        src = a.thumbData || ""
                    annotPopupImg.source = src
                    annotImgDialog.imgTitle = a.title || "(未命名)"
                    annotImgDialog.imgNote = a.note || ""
                    annotImgDialog.imgCoords = a.lng.toFixed(5) + ", " + a.lat.toFixed(5)
                    annotImgDialog.open()
                }

                onBridgeEvent: {
                    eventLog.push({time: new Date().toISOString().slice(11,19), raw: raw})
                    eventLog = eventLog.concat()
                }

                property string debugLoadMsg: ""
                onPageLoaded: {
                    var data = webView.cxxLoadAnnotations()
                    debugLoadMsg = "load: data=" + (data ? data.length : 0)
                    if (data && data.length > 2) {
                        try {
                            loadAnnotationsFromGrouped(data)
                            debugLoadMsg += " ann=" + annotations.length + " paths=" + savedPaths.length
                            refreshAnnotationMarkers()
                            drawSavedPathsOnMap()
                        } catch(e) {
                            debugLoadMsg += " ERROR: " + e
                            console.log("加载标注失败:", e)
                        }
                    } else {
                        debugLoadMsg += " no data"
                    }
                }

            }

            Component {
                id: searchResultDelegate

                Rectangle {
                    width: parent ? parent.width : 260
                    height: 48
                    color: mouseArea.containsMouse ? "#E3F2FD" : "transparent"
                    radius: 3

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            var loc = modelData.location
                            if (loc) {
                                var parts = loc.split(',')
                                if (parts.length === 2) {
                                    searchResultPending = true
                                    if (searchStep === 0) {
                                        nameA_field.text = modelData.name
                                        lngA_field.text = parts[0]
                                        latA_field.text = parts[1]
                                        searchStep = 1
                                    } else {
                                        nameB_field.text = modelData.name
                                        lngB_field.text = parts[0]
                                        latB_field.text = parts[1]
                                        searchStep = 2
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        anchors.topMargin: 4
                        anchors.bottomMargin: 4
                        spacing: 1

                        Label {
                            text: modelData.name || ""
                            font.bold: true
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Label {
                            text: (modelData.address || "") + " · " + (modelData.type || "")
                            font.pixelSize: 10
                            color: "gray"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: annotationDialog
        title: "添加标注"
        standardButtons: Dialog.Save | Dialog.Cancel
        modal: true
        focus: true
        width: 360
        onAccepted: {
            var obj = {
                id: Date.now().toString() + Math.random().toString(36).substr(2, 9),
                lng: pendingAnnotateLng, lat: pendingAnnotateLat,
                title: titleField.text, note: noteField.text,
                tag: tagField.text.trim(),
                thumbData: pendingImageData,
                imageFile: pendingImageFile,
                time: new Date().toISOString()
            }
            if (editIndex >= 0) {
                annotations[editIndex] = obj
                editIndex = -1
            } else {
                annotations.push(obj)
            }
            collectUniqueTags()
            saveAnnotationsGrouped()
            refreshAnnotationMarkers()
            webView.executeScript("addSmallMarker(" + pendingAnnotateLng + "," + pendingAnnotateLat + ",'blue');")
            titleField.text = ""; noteField.text = ""; tagField.text = ""
            pendingImageData = ""; pendingImageFile = ""; imagePreview.source = ""; imagePreview.visible = false
        }
        onRejected: {
            editIndex = -1
            titleField.text = ""; noteField.text = ""; tagField.text = ""
            pendingImageData = ""; pendingImageFile = ""; imagePreview.source = ""; imagePreview.visible = false
        }
        onOpened: {
            focusTimer.start()
        }
        Timer {
            id: focusTimer
            interval: 100
            repeat: false
            onTriggered: titleField.forceActiveFocus()
        }
        ColumnLayout {
            spacing: 8
            TextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: "标注名称"
            }
            TextField {
                id: noteField
                Layout.fillWidth: true
                placeholderText: "备注"
            }
            TextField {
                id: tagField
                Layout.fillWidth: true
                placeholderText: "标签（如：美食、景点）"
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Button {
                    text: "选择图片"
                    Layout.fillWidth: true
                    onClicked: {
                        var json = webView.cxxOpenFileDialog()
                        if (json) {
                            var obj = JSON.parse(json)
                            pendingImageData = obj.dataUri || ""
                            pendingImageFile = obj.relPath || ""
                            if (pendingImageFile) {
                                imagePreview.source = "file:///" + webView.cxxImageFullPath(pendingImageFile)
                                imagePreview.visible = true
                            } else if (pendingImageData) {
                                imagePreview.source = pendingImageData
                                imagePreview.visible = true
                            }
                        }
                    }
                }
                Image {
                    id: imagePreview
                    visible: false
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 60
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 60
                    sourceSize.height: 60
                }
            }
            Label {
                text: (pendingAnnotateLng !== 0 ? pendingAnnotateLng.toFixed(6) + ", " + pendingAnnotateLat.toFixed(6) : "")
                font.pixelSize: 11
                color: "gray"
            }
        }
    }

    Dialog {
        id: pathDialog
        title: "保存路径"
        standardButtons: Dialog.Save | Dialog.Cancel
        modal: true
        width: 280
        onAccepted: savePathFromDialog()
        onRejected: cancelPath()
        onOpened: pathFocusTimer.start()
        Timer {
            id: pathFocusTimer
            interval: 100
            repeat: false
            onTriggered: pathTitleField.forceActiveFocus()
        }
        ColumnLayout {
            spacing: 8
            TextField {
                id: pathTitleField
                Layout.fillWidth: true
                placeholderText: "路径名称"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
            }
            TextField {
                id: pathTagField
                Layout.fillWidth: true
                placeholderText: "标签（默认 TEMP）"
                text: "TEMP"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
            }
            TextField {
                id: pathTimeField
                Layout.fillWidth: true
                placeholderText: "耗时（如：2小时30分）"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
            }
            Label {
                text: currentPath.length > 0 ? currentPath.length + " 个点" : ""
                font.pixelSize: 11; color: "gray"
            }
        }
    }

    Dialog {
        id: pathEditDialog
        title: "编辑路径"
        standardButtons: Dialog.Save | Dialog.Cancel
        modal: true
        width: 300
        onAccepted: updatePathFromEdit()
        onRejected: { pathEditPreview.source = ""; pathEditPreview.visible = false }
        onOpened: pathEditFocusTimer.start()
        Timer {
            id: pathEditFocusTimer
            interval: 100
            repeat: false
            onTriggered: pathEditTitleField.forceActiveFocus()
        }
        ColumnLayout {
            spacing: 8
            TextField {
                id: pathEditTitleField
                Layout.fillWidth: true
                placeholderText: "路径名称"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
            }
            TextField {
                id: pathEditTagField
                Layout.fillWidth: true
                placeholderText: "标签"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
            }
            TextField {
                id: pathEditTimeField
                Layout.fillWidth: true
                placeholderText: "耗时（如：2小时30分）"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
            }
            TextField {
                id: pathEditNoteField
                Layout.fillWidth: true
                placeholderText: "备注"
                onPressed: { webView.releaseBrowserFocus(); forceActiveFocus() }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Button {
                    text: "选择图片"
                    Layout.fillWidth: true
                    onClicked: {
                        var json = webView.cxxOpenFileDialog()
                        if (json) {
                            var obj = JSON.parse(json)
                            pathEditCurImgData = obj.dataUri || ""
                            pathEditCurImgFile = obj.relPath || ""
                            if (pathEditCurImgFile) {
                                pathEditPreview.source = "file:///" + webView.cxxImageFullPath(pathEditCurImgFile)
                                pathEditPreview.visible = true
                            } else if (pathEditCurImgData) {
                                pathEditPreview.source = pathEditCurImgData
                                pathEditPreview.visible = true
                            }
                        }
                    }
                }
                Button {
                    text: "清除"
                    onClicked: {
                        pathEditCurImgData = ""
                        pathEditCurImgFile = ""
                        pathEditPreview.source = ""
                        pathEditPreview.visible = false
                    }
                }
            }
            Image {
                id: pathEditPreview
                visible: false
                Layout.preferredWidth: 80
                Layout.preferredHeight: 80
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 80
                sourceSize.height: 80
            }
        }
    }

    Dialog {
        id: eventLogDialog
        title: "事件记录"
        standardButtons: Dialog.Close
        modal: true
        width: 420
        height: 360
        onClosed: eventLog = [0]
        ColumnLayout {
            anchors.fill: parent
            spacing: 4
            ListView {
                id: eventLogView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: eventLog
                delegate: Rectangle {
                    width: eventLogView.width
                    height: 20
                    color: index % 2 === 0 ? "#F5F5F5" : "white"
                    Label {
                        x: 4
                        text: modelData.time + "  " + modelData.raw
                        font.pixelSize: 11
                        font.family: "Consolas, monospace"
                        elide: Text.ElideRight
                        width: parent.width - 8
                        color: modelData.raw.startsWith("jserr:") ? "#D32F2F" : "#333"
                    }
                }
                ScrollBar.vertical: ScrollBar { }
            }
            Button {
                text: "清空"
                Layout.alignment: Qt.AlignHCenter
                onClicked: eventLog = [0]
            }
        }
    }

    Dialog {
        id: clearConfirmDialog
        title: "确认清除"
        modal: true
        width: 300
        height: 150
        standardButtons: Dialog.NoButton
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            Label {
                text: "确定要清除所有数据吗？\n此操作将删除所有标注、路径和图像。"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 16
                Button {
                    text: "确认"
                    implicitWidth: 70
                    onClicked: { clearConfirmDialog.close(); clearAll() }
                }
                Button {
                    text: "取消"
                    implicitWidth: 70
                    onClicked: clearConfirmDialog.close()
                }
            }
        }
    }

    Dialog {
        id: pathImgDialog
        property string imgTitle: ""
        property string imgNote: ""
        title: imgTitle
        standardButtons: Dialog.Close
        modal: true
        width: 400
        height: 500
        ColumnLayout {
            anchors.fill: parent
            spacing: 6
            Image {
                id: pathPopupImg
                Layout.fillWidth: true
                Layout.fillHeight: true
                fillMode: Image.PreserveAspectFit
            }
            Button {
                text: pathImgDialog.imgNote
                enabled: text.length > 0
                Layout.fillWidth: true
                onClicked: close()
            }
        }
    }

    Dialog {
        id: annotImgDialog
        property string imgTitle: ""
        property string imgNote: ""
        property string imgCoords: ""
        title: imgTitle
        standardButtons: Dialog.Close
        modal: true
        width: 400
        height: 500
        ColumnLayout {
            anchors.fill: parent
            spacing: 6
            Image {
                id: annotPopupImg
                Layout.fillWidth: true
                Layout.fillHeight: true
                fillMode: Image.PreserveAspectFit
            }
            Label {
                text: annotImgDialog.imgCoords
                font.pixelSize: 10
                color: "gray"
            }
            Button {
                text: annotImgDialog.imgNote
                enabled: text.length > 0
                Layout.fillWidth: true
                onClicked: close()
            }
        }
    }

    Dialog {
        id: setupDialog
        title: "使用准备 — 配置 API Key 与域名"
        standardButtons: Dialog.Close
        modal: true
        width: 480
        height: 400
        onVisibleChanged: {
            if (visible) {
                var cfg = webView.cxxGetConfig()
                var obj = JSON.parse(cfg)
                domainField.text = obj.domain || ""
                jsKeyField.text = obj.amapJsKey || ""
                webKeyField.text = obj.amapWebKey || ""
                var valid = webView.cxxIsConfigValid()
                configStatus.text = valid ? "当前配置有效" : "尚未配置，请按下方步骤申请 Key"
                configStatus.color = valid ? "green" : "#E65100"
            }
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Label { text: "请在高德开放平台完成以下准备："; font.bold: true; font.pixelSize: 14 }

            Label {
                text: "1. 登录 console.amap.com → 应用管理 → 创建应用\n"
                    + "2. 添加 JS API（Web端）和 Web Service API 两种 Key\n"
                    + "3. 在 JS API 的白名单中填写你的域名（如 example.com）\n"
                    + "4. 将下方信息复制粘贴后点击保存"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                color: "#555"
            }

            Label {
                id: configStatus
                Layout.fillWidth: true
                font.pixelSize: 12
                font.bold: true
                wrapMode: Text.WordWrap
            }

            GridLayout {
                columns: 2
                columnSpacing: 8
                rowSpacing: 6
                Layout.fillWidth: true

                Label { text: "白名单域名:" }
                TextField {
                    id: domainField
                    Layout.fillWidth: true
                    placeholderText: "example.com"
                }

                Label { text: "JS API Key:" }
                TextField {
                    id: jsKeyField
                    Layout.fillWidth: true
                    placeholderText: "输入 JS API Key（Web端）"
                }

                Label { text: "Web Service Key:" }
                TextField {
                    id: webKeyField
                    Layout.fillWidth: true
                    placeholderText: "输入 Web Service Key"
                }
            }

            Item { Layout.fillHeight: true }

            Button {
                text: "保存配置"
                Layout.fillWidth: true
                highlighted: true
                onClicked: {
                    var ret = webView.cxxSaveConfig(domainField.text, jsKeyField.text, webKeyField.text)
                    if (ret === "ok") {
                        configStatus.text = webView.cxxIsConfigValid() ? "配置已保存，地图将重新加载" : "Key 不完整，请填写所有字段"
                        configStatus.color = webView.cxxIsConfigValid() ? "green" : "#E65100"
                        setupDialog.close()
                    }
                }
            }
        }
    }

}