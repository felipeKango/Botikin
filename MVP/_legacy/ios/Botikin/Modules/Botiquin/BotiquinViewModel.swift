import Foundation
import BotikinKit

@MainActor
final class BotiquinViewModel: ObservableObject {
    @Published var estado: Cargable<[Medicine]> = .inicial
    @Published var busqueda = ""
    @Published var filtro: ExpiryFilter = .todos
    @Published var errorAccion: String?

    private let api = APIClient.shared

    var medicinas: [Medicine] { estado.valor ?? [] }

    var medicinasFiltradas: [Medicine] {
        var lista = ExpiryCalculator.filtrar(medicinas, por: filtro)
        let texto = busqueda.trimmingCharacters(in: .whitespaces)
        if !texto.isEmpty {
            lista = lista.filter {
                $0.nombre.localizedCaseInsensitiveContains(texto)
            }
        }
        return lista.sorted { $0.fechaVencimiento < $1.fechaVencimiento }
    }

    var resumenAlertas: (vencidos: Int, porVencer: Int) {
        ExpiryCalculator.resumenAlertas(medicinas)
    }

    func cargar(token: String?) async {
        guard let token else { return }
        if medicinas.isEmpty { estado = .cargando }
        do {
            let lista: [Medicine] = try await api.select(
                "medicines",
                query: [
                    URLQueryItem(name: "select",
                                 value: "id,nombre,dosis,unidades,fecha_vencimiento,foto_path,viene_de_receta"),
                    URLQueryItem(name: "order", value: "fecha_vencimiento.asc"),
                ],
                accessToken: token)
            estado = .listo(lista)
        } catch {
            if medicinas.isEmpty {
                estado = .error(error.localizedDescription)
            } else {
                errorAccion = error.localizedDescription
            }
        }
    }

    func guardar(_ medicina: Medicine, esNueva: Bool, token: String?) async -> Bool {
        guard let token else { return false }
        errorAccion = nil
        do {
            if esNueva {
                struct Insert: Encodable {
                    let nombre: String
                    let dosis: String
                    let unidades: Int
                    let fecha_vencimiento: Date
                    let viene_de_receta: Bool
                    let user_id: UUID
                }
                // user_id lo exige RLS (with check auth.uid() = user_id)
                guard let userID = usuarioActual else { return false }
                let _: [Medicine] = try await api.insert(
                    "medicines",
                    body: Insert(nombre: medicina.nombre, dosis: medicina.dosis,
                                 unidades: medicina.unidades,
                                 fecha_vencimiento: medicina.fechaVencimiento,
                                 viene_de_receta: medicina.vieneDeReceta,
                                 user_id: userID),
                    accessToken: token)
            } else {
                struct Update: Encodable {
                    let nombre: String
                    let dosis: String
                    let unidades: Int
                    let fecha_vencimiento: Date
                }
                try await api.update(
                    "medicines", id: medicina.id,
                    body: Update(nombre: medicina.nombre, dosis: medicina.dosis,
                                 unidades: medicina.unidades,
                                 fecha_vencimiento: medicina.fechaVencimiento),
                    accessToken: token)
            }
            await cargar(token: token)
            return true
        } catch {
            errorAccion = error.localizedDescription
            return false
        }
    }

    func eliminar(_ medicina: Medicine, token: String?) async {
        guard let token else { return }
        do {
            try await api.delete("medicines", id: medicina.id, accessToken: token)
            await cargar(token: token)
        } catch {
            errorAccion = error.localizedDescription
        }
    }

    var usuarioActual: UUID?
}
