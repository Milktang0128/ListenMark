import Foundation

struct VolcanoVoice: Identifiable {
    let id: String      // voice_type
    let name: String
}

/// 豆包语音合成模型 2.0（_uranus_bigtts）常用音色，节选自官方音色列表（2026.05）。
/// 账号需在火山控制台开通对应音色；也可在设置里手填任意 voice_type。
enum VolcanoVoices {
    static let all: [VolcanoVoice] = [
        .init(id: "zh_female_cancan_uranus_bigtts", name: "灿灿 · 知性女声"),
        .init(id: "zh_female_shuangkuaisisi_uranus_bigtts", name: "爽快思思"),
        .init(id: "zh_female_qingxinnvsheng_uranus_bigtts", name: "清新女声"),
        .init(id: "zh_female_wenrouxiaoya_uranus_bigtts", name: "温柔小雅"),
        .init(id: "zh_female_tianmeitaozi_uranus_bigtts", name: "甜美桃子"),
        .init(id: "zh_female_linjianvhai_uranus_bigtts", name: "邻家女孩"),
        .init(id: "zh_female_gaolengyujie_uranus_bigtts", name: "高冷御姐"),
        .init(id: "zh_female_vv_uranus_bigtts", name: "Vivi · 多语种(中日西)"),
        .init(id: "zh_male_wennuanahu_uranus_bigtts", name: "温暖阿虎 / Alvin"),
        .init(id: "zh_male_shaonianzixin_uranus_bigtts", name: "少年梓辛 / Brayan"),
        .init(id: "zh_male_yuanboxiaoshu_uranus_bigtts", name: "渊博小叔"),
        .init(id: "zh_male_yangguangqingnian_uranus_bigtts", name: "阳光青年"),
        .init(id: "zh_male_ruyaqingnian_uranus_bigtts", name: "儒雅青年"),
        .init(id: "zh_male_cixingjieshuonan_uranus_bigtts", name: "磁性解说 / Morgan"),
        .init(id: "zh_male_shenyeboke_uranus_bigtts", name: "深夜播客"),
        .init(id: "zh_male_xuanyijieshuo_uranus_bigtts", name: "悬疑解说"),
        .init(id: "zh_female_yingyujiaoxue_uranus_bigtts", name: "Tina 老师 · 中英"),
        .init(id: "en_male_tim_uranus_bigtts", name: "Tim · 美式英语"),
        .init(id: "en_female_dacey_uranus_bigtts", name: "Dacey · 美式英语")
    ]
}

enum VolcanoTTSError: Error {
    case notConfigured
    case http(Int, String)
    case api(Int, String)
    case noAudio
}

/// 火山引擎（豆包语音）TTS — HTTP non-streaming `/api/v1/tts`.
/// Auth header is the literal `Bearer;{token}` form; success is code 3000 with
/// base64 audio in `data`.
enum VolcanoTTS {

    static func synthesize(_ text: String) async throws -> Data {
        guard Settings.volcConfigured else { throw VolcanoTTSError.notConfigured }

        var req = URLRequest(url: URL(string: "https://openspeech.bytedance.com/api/v1/tts")!)
        req.httpMethod = "POST"
        req.setValue("Bearer;\(Settings.volcToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "app": [
                "appid": Settings.volcAppId,
                "token": Settings.volcToken,
                "cluster": Settings.volcCluster
            ],
            "user": ["uid": "guoerbuwang"],
            "audio": [
                "voice_type": Settings.volcVoice,
                "encoding": "mp3",
                "speed_ratio": Settings.volcSpeed
            ],
            "request": [
                "reqid": UUID().uuidString,
                "text": text,
                "text_type": "plain",
                "operation": "query"
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw VolcanoTTSError.noAudio }
        guard http.statusCode == 200 else {
            throw VolcanoTTSError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VolcanoTTSError.noAudio
        }
        let code = (obj["code"] as? Int) ?? -1
        guard code == 3000,
              let b64 = obj["data"] as? String,
              let audio = Data(base64Encoded: b64) else {
            throw VolcanoTTSError.api(code, (obj["message"] as? String) ?? "未知错误")
        }
        return audio
    }
}
