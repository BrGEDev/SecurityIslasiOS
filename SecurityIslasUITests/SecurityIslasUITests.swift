//
//  SecurityIslasUITests.swift
//  SecurityIslasUITests
//
//  Flujos que exige el brief: registro (cuenta existente), autorizar la
//  visita en caseta y abrir la pluma. Corren contra el backend de prueba con
//  `-uiTesting YES`, que empieza sin sesión y con los datos de las maquetas.
//  En el simulador no hay Secure Enclave ni Face ID registrado: la llave es de
//  software y la autenticación pasa sola (ver DECISIONES.md).
//

import XCTest

final class SecurityIslasUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "YES"]
        // Avisos de permisos (notificaciones, ubicación): se aceptan.
        addUIInterruptionMonitor(withDescription: "Permisos") { alert in
            for title in ["Permitir", "Allow", "Permitir al usarse la app", "Allow While Using App"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
    }

    /// Bienvenida → celular → SMS → "Hola de nuevo" → permisos → Face ID → Inicio.
    @MainActor
    private func signInAsBrandon() {
        app.launch()

        app.buttons["Continuar"].firstMatch.tap()

        let phone = app.textFields["celular"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        phone.tap()
        phone.typeText("2221234567")
        app.buttons["Enviar código"].tap()

        let code = app.textFields["codigo-sms"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.typeText("123456")

        // 3a: ya tiene cuenta.
        let continueButton = app.buttons["Continuar"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        // 7: permisos (se puede continuar sin activarlos).
        XCTAssertTrue(app.buttons["Continuar"].waitForExistence(timeout: 5))
        app.buttons["Continuar"].tap()

        // 8: crea la llave del dispositivo.
        let activate = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Activar'")).firstMatch
        XCTAssertTrue(activate.waitForExistence(timeout: 5))
        activate.tap()

        // Título grande de Inicio.
        XCTAssertTrue(app.staticTexts["Hola, Brandon"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testRegistroConCuentaExistente() {
        signInAsBrandon()
        XCTAssertTrue(app.buttons["boton-pluma"].exists)
    }

    /// Juan Pérez espera en caseta (datos de la maqueta 9).
    @MainActor
    func testAutorizarVisita() {
        signInAsBrandon()
        let authorize = app.buttons["autorizar-visita"].firstMatch
        XCTAssertTrue(authorize.waitForExistence(timeout: 10))
        authorize.tap()
        app.tap() // dispara el monitor de permisos si apareció alguno

        // Juan pasa a la actividad de hoy y la tarjeta muestra al siguiente en
        // caseta (la pipa que va a varias viviendas, RF-71).
        XCTAssertTrue(app.staticTexts["Pipa Aguas del Valle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Autorizó Brandon"].waitForExistence(timeout: 10))
    }

    /// Posición simulada a 80 m del carril de residentes: abre directo.
    @MainActor
    func testAbrirPluma() {
        signInAsBrandon()
        let gate = app.buttons["boton-pluma"]
        XCTAssertTrue(gate.waitForExistence(timeout: 10))
        let ready = NSPredicate(format: "label CONTAINS 'Abrir pluma'")
        expectation(for: ready, evaluatedWith: gate)
        waitForExpectations(timeout: 10)

        gate.tap()

        let opened = NSPredicate(format: "label CONTAINS 'Pluma abierta'")
        expectation(for: opened, evaluatedWith: gate)
        waitForExpectations(timeout: 10)
    }
}
