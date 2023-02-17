import MuseScore 3.0
import QtQuick 2.2
import QtQuick.Controls 1.1
import Qt.WebSockets 1.0
import "lz-string.js" as LZString
import FileIO 3.0

MuseScore {
    menuPath: "Plugins.Muselab"
    version: "0.0.1"
    description: qsTr("test")
    pluginType: "dialog"
    requiresScore: false
    width: 500
    height: 420
    id: root

    //vars
    property bool dev: true
    property string host: "127.0.0.1:8080"
    property string apiPath: "/api"
    property string token: ""
    property int currentProjectId: -1
    property string log: ""
    //errors
    property bool loginPageHasError: false
    property string loginPageErrorMessage: ""
    property bool signUpPageHasError: false
    property string signUpPageErrorMessage: ""
    property bool projectPageHasError: false
    property string projectPageErrorMessage: ""
    property bool forgotPasswordPageHasError: false
    property string forgotPasswordPageError: ""

    onRun: {
        if ((mscoreMajorVersion == 3) && (mscoreMinorVersion == 0) && (mscoreUpdateVersion < 5)) {
            console.log(qsTr("Unsupported MuseScore version."))
            quit()
        }
    }
    FileIO {
        id: tempXMLFile
        source: tempPath() + "/muselab_project.json"
        onError: console.log(msg)
    }

    WebSocket {
        id: socket
        url: "ws://"+host+"/ws"
        onTextMessageReceived: handleMessage(message)
        onStatusChanged: {
            if (socket.status === WebSocket.Error) {
                logMessage("Error: " + socket.errorString)
            } else if (socket.status === WebSocket.Open) {
                socket.sendTextMessage(JSON.stringify({
                    type: messageTypes.Login, data: {
                        token:root.token, project_id:root.currentProjectId
                    }}))
            } else if (socket.status === WebSocket.Closed) {
                logMessage("Socket closed")
            }
        }
        active: false
    }
    property var messageTypes: ({
        Login:0, Join: 1, Leave: 2, Sync:3
    })
    property var noteTypes: ({
        whole: 4, half: 2, quarter: 1, eighth: 0.5, "16th":0.25, "32nd":0.125, "64th":0.0625, "128th":0.03125,"256th":0.015625
    })
    //websocketMessageHandler
    function handleMessage(message) {
        var response = JSON.parse(message)
        switch (response.type) {
            case messageTypes.Join:
                logMessage(response.data.message)
                socket.sendTextMessage(JSON.stringify({
                    type:messageTypes.Sync, data: {}}))
                break
            case messageTypes.Leave:
                logMessage(response.data.message)
                break
            case messageTypes.Sync:
                handleSync(response.data.score)
                break
        }
    }
    function logMessage(message) {
        root.log = root.log + message + "\n"
    }
    function handleSync(score) {
        var resp = LZString.LZString.decompressFromBase64(score)
        tempXMLFile.write(resp)
        var json = JSON.parse(resp)
        writeScoreFromObject(json)
    }
    function writeScoreFromObject(obj) {
        clearScore()
        //Allow title changing when newScore is implemented
        /*if (obj.hasOwnProperty("credit")) {
            var credit = obj.credit
            for (var i=0; i < credit.length; i++) {
                var creditObj = credit[i]
                curScore.addText(creditObj["credit-type"],creditObj["credit-words"][""])
            }
        }*/
        curScore.startCmd()
        if (obj.hasOwnProperty("part-list")) {
            var partList = obj["part-list"]
            if (partList.hasOwnProperty("score-part")) {
                var scorePart = partList["score-part"]
                if(Array.isArray(scorePart)){
                    for (var i=0; i < scorePart.length; i++) {
                        var scorePartObj = scorePart[i]
                        curScore.appendPart(scorePartObj["score-instrument"]["instrument-name"].toLowerCase())
                    }
                }
                else{
                    var scorePartObj = scorePart;
                    curScore.appendPart(scorePartObj["score-instrument"]["instrument-name"].toLowerCase())
                }
            }
        }
        var cursor = curScore.newCursor()
        var hasMeasures = false;
        if (obj.hasOwnProperty("part")) {
             var part = obj["part"]
             if(Array.isArray(part)){
                for (var i=0; i < part.length; i++) {
                    var measure = part[i]["measure"]
                    if(Array.isArray(measure)){
                        if(!hasMeasures){ 
                        curScore.appendMeasures(measure.length)
                        hasMeasures = true
                        }
                        writeObject(cursor,i,measure)
                    }
                    else{
                        if(!hasMeasures) curScore.appendMeasures(1);
                        writeObject(cursor,i,measure)
                    }
                }
             }
             else{
                    var measure = part["measure"]
                    if(Array.isArray(measure)){
                        if(!hasMeasures){ 
                        curScore.appendMeasures(measure.length)
                        hasMeasures = true
                        }
                        writeObject(cursor,i,measure)
                    }
                    else{
                        if(!hasMeasures) curScore.appendMeasures(1);
                        writeObject(cursor,i,measure)
                    }
             }
        }  
        curScore.endCmd()
    }
    function writeObject(cursor, partIdx, measureArr){
        //var idx = curScore.nstaves-1
        cursor.staffIdx = partIdx;
        cursor.rewind(0)
        var currentAttributes = {ts:{}}
        for (var i=0; i < measureArr.length; i++) {
            var measure = measureArr[i];
            if(measure.hasOwnProperty("attributes")){
                var attributes = measure.attributes;
                if(attributes.hasOwnProperty("key")){
                    var ks = newElement(Element.KEYSIG);
                    ks.KeySig = parseInt(attributes.key["fifths"])
                    cursor.add(ks)
                }
                if(attributes.hasOwnProperty("time")){
                    var ts = newElement(Element.TIMESIG)
                    ts.timesig = fraction(parseInt(attributes.time["beats"]), parseInt(attributes.time["beat-type"]))
                    currentAttributes.ts.numerator = parseInt(attributes.time["beats"]);
                    currentAttributes.ts.denominator = parseInt(attributes.time["beat-type"]);
                    cursor.add(ts)
                }                
                if(attributes.hasOwnProperty("divisions")){
                    currentAttributes.divisions = parseInt(attributes["divisions"])
                }  
            }
            /*if(measure.hasOwnProperty("direction")){
                var attributes = measure.attributes;
                if(attributes.hasOwnProperty("time")){
                    var ts = newElement(Element.TIMESIG)
                    ts.timesig = fraction(parseInt(attributes.time["beats"]), parseInt(attributes.time["beat-type"]))
                    cursor.add(ts)
                    cursor.prev()
                }            
            }*/
            if(measure.hasOwnProperty("note")){
                if(Array.isArray(measure["note"])){
                    var noteArr = measure["note"]
                    for (var j=0; j < currentAttributes.ts.numerator; j++) {
                        if(j < noteArr.length){
                            var note = noteArr[j];
                            var duration = parseInt(note.duration);
                            var denominator = parseInt(currentAttributes.divisions) * currentAttributes.ts.denominator
                            cursor.setDuration(parseInt(note.duration),denominator);
                            if(note.hasOwnProperty("rest")){
                                cursor.addRest();
                            }
                            else{                         
                                cursor.addNote(convertPitchToMidi(note));
                            }
                        }
                        else{
                            var denominator = parseInt(currentAttributes.divisions) * currentAttributes.ts.denominator
                            cursor.setDuration(1,denominator);
                            cursor.addRest();
                        }
                    }
                }
                else{
                    var note = measure["note"]
                    var duration = parseInt(note.duration);
                    var denominator = parseInt(currentAttributes.divisions) * currentAttributes.ts.denominator
                    cursor.setDuration(parseInt(note.duration),denominator);
                    if(note.hasOwnProperty("rest")){
                        cursor.addRest();
                    }
                    else{                         
                        cursor.addNote(convertPitchToMidi(note));
                    }
                }
            }
        }
    }
    function convertPitchToMidi(note) {
        var noteNumber = getNoteNumber(note.pitch.step, (note.hasOwnProperty("accidental") ? note.accidental : ""));
        var midiPitch = (parseInt(note.pitch.octave) + 1) * 12 + noteNumber;
        return midiPitch;
    }
    function getNoteNumber(step, type = null) {
        var notesSharp = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
        var notesFlat = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
        var newStep = step;
        if(type !== ""){
            if(type == "flat") newStep += "b"
            if(type == "sharp") newStep += "#"
        }
        var noteIndex = type == "flat" ? notesFlat.indexOf(newStep) : notesSharp.indexOf(newStep);
        return noteIndex
    }
    function clearScore(){
        curScore.startCmd()
        curScore.selection.selectRange(curScore.firstSegment.tick, curScore.lastSegment.tick+1, 0, curScore.nmeasures)
        cmd("time-delete")
        cmd("del-empty-measures")
        curScore.endCmd() 
    }
    function signUp(username, email, password) {
        var content = {
            "username":username,"email":email,"password":password
        }
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState == XMLHttpRequest.DONE) {
                if (request.status === 200) {
                    var response = request.responseText
                    var json = JSON.parse(response)
                    if (root.signUpPageHasError) {
                        root.signUpPageHasError = false
                        root.signUpPageErrorMessage = ""
                    }
                    stackView.push(loginPage)
                } else {
                    root.signUpPageHasError = true
                    root.signUpPageErrorMessage = "Email or Username already exists!"
                }
            }
        }
        request.open("POST", getApiUrl("/auth/register"), true)
        request.setRequestHeader("Content-Type", "application/json")
        request.send(JSON.stringify(content))
    }
    function forgotPassword(email) {
        var content = {
            "email":email
        }
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState == XMLHttpRequest.DONE) {
                if (request.status === 200) {
                    if (root.forgotPasswordPageHasError) {
                        root.forgotPasswordPageHasError = false
                        root.forgotPasswordPageError = ""
                    }
                    stackView.push(loginPage)
                } else {
                    root.forgotPasswordPageHasError = true
                    root.forgotPasswordPageError = "Email not found!"
                }
            }
        }
        request.open("POST", getApiUrl("/auth/forgot_password"), true)
        request.setRequestHeader("Content-Type", "application/json")
        request.send(JSON.stringify(content))
    }
    function login(username, password) {
        var content = {
            "username":username,"password":password
        }
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState == XMLHttpRequest.DONE) {
                if (request.status === 200) {
                    if (root.token !== "") return
                    var response = request.responseText
                    var json = JSON.parse(response)
                    if (root.loginPageHasError) {
                        root.loginPageHasError = false
                        root.loginPageErrorMessage = ""
                    }
                    root.token = json.accessToken
                    stackView.push(projectPage)
                    getProjects()
                } else {
                    root.loginPageHasError = true
                    root.loginPageErrorMessage = "Username or password is incorrect."
                }
            }
        }
        request.open("POST", getApiUrl("/auth/login"), true)
        request.setRequestHeader("Content-Type", "application/json")
        request.send(JSON.stringify(content))
    }

    function getProjects() {
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState == XMLHttpRequest.DONE) {
                if (request.status === 200) {
                    var response = request.responseText
                    var json = JSON.parse(response)
                    for (let i=0;i<json.length;i++) projectListModel.append({
                        key: json[i].name, value: json[i].projectId
                    })
                } else {
                    root.projectPageHasError = true
                    root.projectPageErrorMessage = "Invalid auth token."
                }
            }
        }
        request.open("GET", getApiUrl("/projects/list"), true)
        request.setRequestHeader("Authorization", "Bearer "+root.token)
        request.send()
    }

    function createProject(name) {
        var content = {
            "name":name
        }
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState == XMLHttpRequest.DONE) {
                if (request.status === 200) {
                    var response = request.responseText
                    var json = JSON.parse(response)
                    root.currentProjectId = json.id
                    stackView.push(currentProjectPage)
                    startSocket()
                } else {
                    root.projectPageHasError = true
                    root.projectPageErrorMessage = "Invalid auth token."
                }
            }
        }
        request.open("POST", getApiUrl("/projects/create"), true)
        request.setRequestHeader("Content-Type", "application/json")
        request.setRequestHeader("Authorization", "Bearer "+root.token)
        request.send(JSON.stringify(content))
    }

    function startSocket() {
        socket.active = true
    }

    function getApiUrl(path) {
        return (dev ? "http" : "https") +"://"+host+apiPath+path
    }
    StackView {
        id: stackView
        width: root.width
        height: root.height
        initialItem: loginPage

        Component {
            id: loginPage
            Column {
                spacing: 20
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Muselab Username"
                    font.bold: true
                }
                TextField {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: usernameField
                    placeholderText: "Enter username"
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Muselab Password"
                    font.bold: true
                }
                TextField {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: passwordField
                    placeholderText: "Enter password"
                    echoMode: TextInput.Password
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: errorText
                    visible: root.loginPageHasError
                    color: "red"
                    text: root.loginPageErrorMessage
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20

                    Button {
                        text: "Login"
                        onClicked: {
                            if (usernameField.text.length < 3 || passwordField.text.length < 6) {
                                root.loginPageHasError = true
                                root.loginPageErrorMessage = "Username and password cannot be empty."
                            } else {
                                login(usernameField.text, passwordField.text)
                            }
                        }
                    }

                    Button {
                        text: "Forgot Password"
                        onClicked: {
                            stackView.push(forgotPasswordPage)
                        }
                    }
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Sign Up"
                    onClicked: {
                        stackView.push(signUpPage)
                    }
                }
            }
        }
        Component {
            id: forgotPasswordPage
            Column {
                spacing: 20
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Muselab Email"
                    font.bold: true
                }
                TextField {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: emailField
                    placeholderText: "Enter email"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: errorText
                    visible: root.forgotPasswordPageHasError
                    color: "red"
                    text: root.forgotPasswordPageError
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Reset"
                    onClicked: {
                        if (!(/^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/g.test(emailField.text))) {
                            root.forgotPasswordPageHasError = true
                            root.forgotPasswordPageError = "Please enter a valid email."
                        } else {
                            forgotPassword(emailField.text)
                        }
                    }
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Login"
                    onClicked: {
                        stackView.push(loginPage)
                    }
                }
            }
        }
        Component {
            id: signUpPage
            Column {
                spacing: 20
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Email"
                    font.bold: true
                }
                TextField {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: signUpEmailField
                    placeholderText: "Enter email"
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Muselab Username"
                    font.bold: true
                }
                TextField {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: signUpUsernameField
                    placeholderText: "Enter username"
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Muselab Password"
                    font.bold: true
                }
                TextField {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: signUpPasswordField
                    placeholderText: "Enter password"
                    echoMode: TextInput.Password
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Confirm Muselab Password"
                    font.bold: true
                }
                TextField {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: confirmPasswordField
                    placeholderText: "Confirm password"
                    echoMode: TextInput.Password
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: errorText
                    visible: root.signUpPageHasError
                    color: "red"
                    text: root.signUpPageErrorMessage
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Sign Up"
                    onClicked: {
                        if (!(/^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/g.test(signUpEmailField.text))) {
                            root.signUpPageHasError = true
                            root.signUpPageErrorMessage = "Please enter a valid email."
                        } else if (signUpUsernameField.text.length < 3) {
                            root.signUpPageHasError = true
                            root.signUpPageErrorMessage = "Please enter a username."
                        } else if (signUpPasswordField.text.length < 6) {
                            root.signUpPageHasError = true
                            root.signUpPageErrorMessage = "Please enter a password."
                        } else if (confirmPasswordField.text === "") {
                            root.signUpPageHasError = true
                            root.signUpPageErrorMessage = "Please confirm your password."
                        } else if (signUpPasswordField.text !== confirmPasswordField.text) {
                            root.signUpPageHasError = true
                            root.signUpPageErrorMessage = "Passwords do not match."
                        } else {
                            signUp(signUpUsernameField.text, signUpEmailField.text, signUpPasswordField.text)
                        }
                    }
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Login"
                    onClicked: {
                        stackView.push(loginPage)
                    }
                }
            }
        }
        Component {
            id: projectPage
            Column {
                spacing: 40
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Select a Project"
                        font.bold: true
                    }
                    ComboBox {
                        id: projectList
                        currentIndex: -1
                        anchors.horizontalCenter: parent.horizontalCenter
                        textRole: "key"
                        model: projectListModel
                    }
                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Select"
                        onClicked: {
                            if (projectList.currentIndex > -1) {
                                root.currentProjectId = projectListModel.get(projectList.currentIndex).value
                                stackView.push(currentProjectPage)
                                startSocket()
                            } else {
                                root.projectPageHasError = true
                                root.projectPageErrorMessage = "Please select a project."
                            }
                        }
                    }
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Create new Project"
                        font.bold: true
                    }
                    TextField {
                        anchors.horizontalCenter: parent.horizontalCenter
                        id: createProjectField
                        placeholderText: "Enter title"
                    }
                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Create"
                        onClicked: {
                            if (!createProjectField.text === "") {
                                root.projectPageHasError = true
                                root.projectPageErrorMessage = "Please enter a project name."
                            } else {
                                createProject(createProjectField.text)
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        id: errorText
                        visible: root.projectPageHasError
                        color: "red"
                        text: root.projectPageErrorMessage
                    }
                }
            }
        }
        Component {
            id: currentProjectPage
            Column {
                spacing: 20
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Project Log"
                    font.bold: true
                }
                TextArea {
                    anchors.horizontalCenter: parent.horizontalCenter
                    id: logBox
                    width: parent.width / 2
                    readOnly: true
                    text: log
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Logout"
                    onClicked: {
                        socket.active = false
                        root.token = ""
                        root.currentProjectId = -1
                        stackView.push(loginPage)
                    }
                }
            }
        }
    }
    ListModel {
        id: projectListModel
    }
}