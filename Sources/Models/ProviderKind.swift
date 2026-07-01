import Foundation

enum ProviderKind: String, CaseIterable, Identifiable, Codable {
    case deepseek, moonshot, zhipu, zai, codex, claudeCode, openrouter, siliconflow
    case gemini, openai, qwen, anthropic, mistral, xai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek:    return "DeepSeek"
        case .moonshot:    return "Kimi (Moonshot)"
        case .zhipu:       return "GLM (Zhipu)"
        case .zai:         return "GLM (Z.ai)"
        case .codex:       return "Codex"
        case .claudeCode:  return "Claude Code"
        case .openrouter:  return "OpenRouter"
        case .siliconflow: return "SiliconFlow"
        case .gemini:      return "Google Gemini"
        case .openai:      return "OpenAI"
        case .qwen:        return "Qwen (DashScope)"
        case .anthropic:   return "Anthropic"
        case .mistral:     return "Mistral"
        case .xai:         return "xAI Grok"
        }
    }

    var shortLabel: String {
        switch self {
        case .deepseek:    return "DS"
        case .moonshot:    return "KI"
        case .zhipu:       return "GLM"
        case .zai:         return "Z"
        case .codex:       return "CX"
        case .claudeCode:  return "CC"
        case .openrouter:  return "OR"
        case .siliconflow: return "SF"
        case .gemini:      return "G"
        case .openai:      return "AI"
        case .qwen:        return "QW"
        case .anthropic:   return "AN"
        case .mistral:     return "M"
        case .xai:         return "X"
        }
    }

    var accentColorHex: String {
        switch self {
        case .deepseek:    return "#4D6BFE"
        case .moonshot:    return "#111827"
        case .zhipu:       return "#3F6BFF"
        case .zai:         return "#7C3AED"
        case .codex:       return "#10A37F"
        case .claudeCode:  return "#D97757"
        case .openrouter:  return "#6366F1"
        case .siliconflow: return "#FF6A00"
        case .gemini:      return "#1A73E8"
        case .openai:      return "#10A37F"
        case .qwen:        return "#615CED"
        case .anthropic:   return "#D97757"
        case .mistral:     return "#FF7000"
        case .xai:         return "#111111"
        }
    }

    var keyAcquireURL: String {
        switch self {
        case .deepseek:    return "https://platform.deepseek.com/api_keys"
        case .moonshot:    return "https://platform.moonshot.ai/console/api-keys"
        case .zhipu:       return "https://open.bigmodel.cn/usercenter/apikeys"
        case .zai:         return "https://z.ai/manage/apikey"
        case .codex:       return "https://chatgpt.com/codex/settings/usage"
        case .claudeCode:  return "https://claude.com/settings"
        case .openrouter:  return "https://openrouter.ai/keys"
        case .siliconflow: return "https://cloud.siliconflow.cn/account/ak"
        case .gemini:      return "https://aistudio.google.com/app/apikey"
        case .openai:      return "https://platform.openai.com/api-keys"
        case .qwen:        return "https://dashscope.console.aliyun.com/apiKey"
        case .anthropic:   return "https://console.anthropic.com/settings/keys"
        case .mistral:     return "https://console.mistral.ai/api-keys"
        case .xai:         return "https://console.x.ai"
        }
    }

    var summary: String {
        switch self {
        case .deepseek, .moonshot, .siliconflow:
            return "Reports account balance."
        case .zhipu, .zai:
            return "Reports GLM Coding Plan 5-hour token quota."
        case .codex:
            return "Reads local Codex usage snapshots from ~/.codex logs."
        case .claudeCode:
            return "Reads local Claude Code rate-limit snapshots from ~/.claude logs."
        case .openrouter:
            return "Reports spend limit & usage."
        case .gemini, .openai, .qwen, .anthropic, .mistral, .xai:
            return "No public quota API — key validation only."
        }
    }

    var requiresAPIKey: Bool {
        self != .codex && self != .claudeCode
    }

    var credentialLabel: String {
        switch self {
        case .zhipu, .zai:
            return "Anthropic auth token"
        case .codex:
            return "No credential required"
        case .claudeCode:
            return "No credential required"
        default:
            return "API key"
        }
    }

    var credentialPlaceholder: String {
        switch self {
        case .zhipu, .zai:
            return "ANTHROPIC_AUTH_TOKEN"
        case .codex:
            return "Uses local ~/.codex logs"
        case .claudeCode:
            return "Uses local ~/.claude logs"
        default:
            return "sk-…"
        }
    }
}
