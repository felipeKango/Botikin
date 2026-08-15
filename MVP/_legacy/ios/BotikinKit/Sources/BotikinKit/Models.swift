import Foundation

// MARK: - Planes y suscripción

public enum Plan: String, Codable, CaseIterable, Sendable {
    case free, basic, pro

    public var nombre: String {
        switch self {
        case .free: "Gratis"
        case .basic: "Básico"
        case .pro: "Pro"
        }
    }

    /// Tokens mensuales del plan. -1 = ilimitado.
    public var tokensMensuales: Int {
        switch self {
        case .free: 500
        case .basic: 5_000
        case .pro: -1
        }
    }

    public var precioCLP: Int {
        switch self {
        case .free: 0
        case .basic: 4_990
        case .pro: 9_990
        }
    }

    public var incluyeWhatsApp: Bool { self != .free }
}

public struct Subscription: Codable, Equatable, Sendable {
    public var plan: Plan
    public var estado: String
    public var tokensTotal: Int
    public var tokensUsados: Int
    public var fechaRenovacion: Date
    public var codigoDescuentoUsado: String?

    public init(plan: Plan, estado: String = "active", tokensTotal: Int,
                tokensUsados: Int, fechaRenovacion: Date,
                codigoDescuentoUsado: String? = nil) {
        self.plan = plan
        self.estado = estado
        self.tokensTotal = tokensTotal
        self.tokensUsados = tokensUsados
        self.fechaRenovacion = fechaRenovacion
        self.codigoDescuentoUsado = codigoDescuentoUsado
    }

    enum CodingKeys: String, CodingKey {
        case plan, estado
        case tokensTotal = "tokens_total"
        case tokensUsados = "tokens_usados"
        case fechaRenovacion = "fecha_renovacion"
        case codigoDescuentoUsado = "codigo_descuento_usado"
    }
}

// MARK: - Medicamentos

public struct Medicine: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var nombre: String
    public var dosis: String
    public var unidades: Int
    public var fechaVencimiento: Date
    public var fotoPath: String?
    public var vieneDeReceta: Bool

    public init(id: UUID = UUID(), nombre: String, dosis: String = "",
                unidades: Int = 0, fechaVencimiento: Date,
                fotoPath: String? = nil, vieneDeReceta: Bool = false) {
        self.id = id
        self.nombre = nombre
        self.dosis = dosis
        self.unidades = unidades
        self.fechaVencimiento = fechaVencimiento
        self.fotoPath = fotoPath
        self.vieneDeReceta = vieneDeReceta
    }

    enum CodingKeys: String, CodingKey {
        case id, nombre, dosis, unidades
        case fechaVencimiento = "fecha_vencimiento"
        case fotoPath = "foto_path"
        case vieneDeReceta = "viene_de_receta"
    }
}

// MARK: - Recetas

public struct PrescriptionMedicine: Codable, Identifiable, Equatable, Sendable {
    public var nombre: String
    public var dosis: String
    public var posologia: String
    public var indicaciones: String
    public var yaLoTienes: Bool

    public var id: String { "\(nombre)-\(dosis)" }

    enum CodingKeys: String, CodingKey {
        case nombre, dosis, posologia, indicaciones
        case yaLoTienes = "ya_lo_tienes"
    }

    public init(nombre: String, dosis: String, posologia: String,
                indicaciones: String, yaLoTienes: Bool = false) {
        self.nombre = nombre
        self.dosis = dosis
        self.posologia = posologia
        self.indicaciones = indicaciones
        self.yaLoTienes = yaLoTienes
    }
}

public struct PrescriptionAnalysis: Codable, Equatable, Sendable {
    public var medico: String
    public var fechaReceta: String?
    public var medicamentos: [PrescriptionMedicine]

    enum CodingKeys: String, CodingKey {
        case medico
        case fechaReceta = "fecha_receta"
        case medicamentos
    }

    public init(medico: String, fechaReceta: String?, medicamentos: [PrescriptionMedicine]) {
        self.medico = medico
        self.fechaReceta = fechaReceta
        self.medicamentos = medicamentos
    }
}

// MARK: - Tokens

public enum TokenAction: String, Codable, CaseIterable, Sendable {
    case prescriptionAnalysis = "prescription_analysis"
    case cabinetAnalysis = "cabinet_analysis"
    case whatsappMessage = "whatsapp_message"
    case assistantChat = "assistant_chat"

    public var nombre: String {
        switch self {
        case .prescriptionAnalysis: "Análisis de receta"
        case .cabinetAnalysis: "Análisis botiquín"
        case .whatsappMessage: "Mensaje WhatsApp"
        case .assistantChat: "Chat asistente"
        }
    }

    /// Costo fijo que cobra el backend (mismo valor que CHARGE_COST
    /// en las Edge Functions).
    public var costo: Int {
        switch self {
        case .prescriptionAnalysis: 1_000
        case .cabinetAnalysis: 400
        case .whatsappMessage: 300
        case .assistantChat: 200
        }
    }
}

public struct TokenUsageEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tipoAccion: TokenAction
    public var tokensConsumidos: Int
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case tipoAccion = "tipo_accion"
        case tokensConsumidos = "tokens_consumidos"
        case createdAt = "created_at"
    }

    public init(id: UUID = UUID(), tipoAccion: TokenAction,
                tokensConsumidos: Int, createdAt: Date) {
        self.id = id
        self.tipoAccion = tipoAccion
        self.tokensConsumidos = tokensConsumidos
        self.createdAt = createdAt
    }
}

// MARK: - WhatsApp

public enum WhatsAppMessageType: String, Codable, CaseIterable, Sendable {
    case expiryAlert = "expiry_alert"
    case reminder = "reminder"
    case aiSuggestion = "ai_suggestion"

    public var nombre: String {
        switch self {
        case .expiryAlert: "Alerta vencimiento"
        case .reminder: "Recordatorio"
        case .aiSuggestion: "Sugerencia AI"
        }
    }
}

public enum DeliveryStatus: String, Codable, Sendable {
    case sent = "sent"
    case delivered = "delivered"
    case failed = "failed"

    public var nombre: String {
        switch self {
        case .sent: "Enviado"
        case .delivered: "Entregado"
        case .failed: "Fallido"
        }
    }
}

public struct WhatsAppMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var telefono: String
    public var texto: String
    public var tipo: WhatsAppMessageType
    public var estadoEntrega: DeliveryStatus
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, telefono, texto, tipo
        case estadoEntrega = "estado_entrega"
        case createdAt = "created_at"
    }

    public init(id: UUID = UUID(), telefono: String, texto: String,
                tipo: WhatsAppMessageType, estadoEntrega: DeliveryStatus,
                createdAt: Date) {
        self.id = id
        self.telefono = telefono
        self.texto = texto
        self.tipo = tipo
        self.estadoEntrega = estadoEntrega
        self.createdAt = createdAt
    }
}
