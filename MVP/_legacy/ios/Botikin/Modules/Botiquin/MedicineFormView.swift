import SwiftUI
import BotikinKit

/// Alta y edición de un remedio del botiquín.
struct MedicineFormView: View {
    @ObservedObject var modelo: BotiquinViewModel
    var medicina: Medicine?

    @EnvironmentObject private var sesion: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var nombre = ""
    @State private var dosis = ""
    @State private var unidades = 1
    @State private var fechaVencimiento = Calendar.current.date(
        byAdding: .month, value: 6, to: .now)!
    @State private var guardando = false

    private var esNueva: Bool { medicina == nil }
    private var valido: Bool {
        !nombre.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Remedio") {
                    TextField("Nombre (ej: Paracetamol)", text: $nombre)
                    TextField("Dosis (ej: 500mg)", text: $dosis)
                    Stepper("Unidades: \(unidades)", value: $unidades, in: 0...999)
                }
                Section("Vencimiento") {
                    DatePicker("Fecha de vencimiento",
                               selection: $fechaVencimiento,
                               displayedComponents: .date)
                        .environment(\.locale, Formato.localeChile)
                }
                if let error = modelo.errorAccion {
                    Section {
                        Text(error).foregroundStyle(Color.botikinRojo)
                    }
                }
            }
            .navigationTitle(esNueva ? "Nuevo remedio" : "Editar remedio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await guardar() }
                    } label: {
                        if guardando { ProgressView() } else { Text("Guardar") }
                    }
                    .disabled(!valido || guardando)
                }
            }
            .onAppear {
                if let medicina {
                    nombre = medicina.nombre
                    dosis = medicina.dosis
                    unidades = medicina.unidades
                    fechaVencimiento = medicina.fechaVencimiento
                }
            }
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        let nueva = Medicine(
            id: medicina?.id ?? UUID(),
            nombre: nombre.trimmingCharacters(in: .whitespaces),
            dosis: dosis.trimmingCharacters(in: .whitespaces),
            unidades: unidades,
            fechaVencimiento: fechaVencimiento,
            vieneDeReceta: medicina?.vieneDeReceta ?? false)
        if await modelo.guardar(nueva, esNueva: esNueva, token: sesion.accessToken) {
            dismiss()
        }
    }
}
