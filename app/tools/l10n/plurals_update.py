"""2026-10-26：带数量的句子改成嵌入“N 小节”/时长，并补复数变体。一次性迁移脚本，保留作记录。"""
import json, os
here = os.path.dirname(os.path.abspath(__file__))
OLD = ['%lld → %lld BPM · 每 %lld 小节 %@%lld', '%lld 小节后到达目标 · %@', '今天已练够 %lld 分钟', '今天已练够 %lld 分钟，已自动停止',
       '有声 %lld 小节 · 静音 %lld 小节', '目标 %lld 分钟，到时提醒', '目标 %lld 分钟，到时提醒并停止', '第 %lld 小节 · 还剩 %lld 小节']
NEW_KEYS = ['%lld → %lld BPM · 每 %@ %@%lld', '%@后到达目标 · %@', '今天已练够 %@', '今天已练够 %@，已自动停止',
            '有声 %@ · 静音 %@', '目标 %@，到时提醒', '目标 %@，到时提醒并停止', '第 %lld 小节 · 还剩 %@']
new = {
 "zh-Hant": ["%lld → %lld BPM · 每 %@ %@%lld", "%@後到達目標 · %@", "今天已練滿 %@", "今天已練滿 %@，已自動停止",
             "有聲 %@ · 靜音 %@", "目標 %@，到時提醒", "目標 %@，到時提醒並停止", "第 %lld 小節 · 還剩 %@"],
 "en": ["%lld → %lld BPM · every %@ %@%lld", "Reaches target in %@ · %@", "You've practiced %@ today", "You've practiced %@ today, stopped automatically",
        "%@ audible · %@ muted", "Goal %@, remind when reached", "Goal %@, remind and stop when reached", "Bar %lld · %@ left"],
 "ja": ["%lld → %lld BPM · %@ごと %@%lld", "%@後に目標に到達 · %@", "今日は %@ 練習しました", "今日は %@ 練習しました。自動で停止しました",
        "発音 %@ · ミュート %@", "目標 %@、時間になったら通知", "目標 %@、時間になったら通知して停止", "%lld 小節目 · 残り %@"],
 "ko": ["%lld → %lld BPM · %@마다 %@%lld", "%@ 후 목표 도달 · %@", "오늘 %@ 연습했어요", "오늘 %@ 연습했어요. 자동으로 정지했습니다",
        "소리 %@ · 무음 %@", "목표 %@, 도달 시 알림", "목표 %@, 도달 시 알림 후 정지", "%lld마디 · %@ 남음"],
 "es": ["%lld → %lld BPM · cada %@ %@%lld", "Objetivo en %@ · %@", "Hoy has practicado %@", "Hoy has practicado %@; detenido automáticamente",
        "Sonido: %@ · silencio: %@", "Objetivo de %@, avisa al llegar", "Objetivo de %@, avisa y detiene al llegar", "Compás %lld · restante: %@"],
 "fr": ["%lld → %lld BPM · toutes les %@ %@%lld", "Objectif dans %@ · %@", "Vous avez travaillé %@ aujourd’hui", "Vous avez travaillé %@ aujourd’hui ; arrêt automatique",
        "Son : %@ · silence : %@", "Objectif de %@, prévient à l’échéance", "Objectif de %@, prévient et arrête à l’échéance", "Mesure %lld · encore %@"],
 "de": ["%lld → %lld BPM · alle %@ %@%lld", "%@ bis zum Ziel · %@", "Heute %@ geübt", "Heute %@ geübt, automatisch gestoppt",
        "%@ hörbar · %@ stumm", "Ziel %@, Erinnerung bei Erreichen", "Ziel %@, Erinnerung und Stopp bei Erreichen", "Takt %lld · noch %@"],
 "pt-BR": ["%lld → %lld BPM · a cada %@ %@%lld", "Meta em %@ · %@", "Você praticou %@ hoje", "Você praticou %@ hoje, parado automaticamente",
           "Som: %@ · mudo: %@", "Meta de %@, avisa ao atingir", "Meta de %@, avisa e para ao atingir", "Compasso %lld · restante: %@"],
 "it": ["%lld → %lld BPM · ogni %@ %@%lld", "Obiettivo tra %@ · %@", "Hai studiato %@ oggi", "Hai studiato %@ oggi, fermato automaticamente",
        "Suono: %@ · silenzio: %@", "Obiettivo %@, avviso al raggiungimento", "Obiettivo %@, avviso e stop al raggiungimento", "Battuta %lld · restanti: %@"],
 "ru": ["%lld → %lld BPM · каждые %@ %@%lld", "Цель через %@ · %@", "Сегодня уже %@ практики", "Сегодня уже %@ практики, остановлено автоматически",
        "Звучит %@ · тишина %@", "Цель %@, напомнить по достижении", "Цель %@, напомнить и остановить по достижении", "Такт %lld · осталось %@"],
 "tr": ["%lld → %lld BPM · her %@ %@%lld", "%@ sonra hedefe ulaşır · %@", "Bugün %@ çalıştınız", "Bugün %@ çalıştınız, otomatik durduruldu",
        "Sesli %@ · sessiz %@", "Hedef %@, ulaşılınca hatırlat", "Hedef %@, ulaşılınca hatırlat ve durdur", "%lld. ölçü · %@ kaldı"],
}
# 复数变体：只写该语言用到的类别（CLDR）；ja/ko/zh/tr 只有 other
plural = {
 "%lld 小节": {
  "zh-Hant": {"other": "%lld 小節"}, "ja": {"other": "%lld 小節"}, "ko": {"other": "%lld마디"}, "tr": {"one": "%lld ölçü", "other": "%lld ölçü"},
  "en": {"one": "%lld bar", "other": "%lld bars"},
  "de": {"one": "%lld Takt", "other": "%lld Takte"},
  "es": {"one": "%lld compás", "many": "%lld compases", "other": "%lld compases"},
  "fr": {"one": "%lld mesure", "many": "%lld mesures", "other": "%lld mesures"},
  "pt-BR": {"one": "%lld compasso", "many": "%lld compassos", "other": "%lld compassos"},
  "it": {"one": "%lld battuta", "many": "%lld battute", "other": "%lld battute"},
  "ru": {"one": "%lld такт", "few": "%lld такта", "many": "%lld тактов", "other": "%lld такта"},
 },
 "查看全部 %lld 条记录": {
  "zh-Hant": {"other": "查看全部 %lld 筆記錄"}, "ja": {"other": "%lld 件の記録をすべて表示"}, "ko": {"other": "기록 %lld개 모두 보기"},
  "tr": {"one": "Kaydı gör (%lld)", "other": "Tüm kayıtları gör (%lld)"},
  "en": {"one": "View %lld session", "other": "View all %lld sessions"},
  "de": {"one": "%lld Eintrag anzeigen", "other": "Alle %lld Einträge anzeigen"},
  "es": {"one": "Ver %lld sesión", "many": "Ver las %lld sesiones", "other": "Ver las %lld sesiones"},
  "fr": {"one": "Voir %lld séance", "many": "Voir les %lld séances", "other": "Voir les %lld séances"},
  "pt-BR": {"one": "Ver %lld registro", "many": "Ver todos os %lld registros", "other": "Ver todos os %lld registros"},
  "it": {"one": "Mostra %lld sessione", "many": "Mostra tutte le %lld sessioni", "other": "Mostra tutte le %lld sessioni"},
  "ru": {"one": "Показать %lld запись", "few": "Показать все %lld записи", "many": "Показать все %lld записей", "other": "Показать все %lld записи"},
 },
}
for lang, values in new.items():
    p = os.path.join(here, "translations", f"{lang}.json")
    t = json.load(open(p))
    for k in OLD: t.pop(k, None)
    for k, v in zip(NEW_KEYS, values): t[k] = v
    for k, forms in plural.items(): t[k] = forms[lang]
    json.dump(t, open(p, "w"), ensure_ascii=False, indent=1)
print("updated", len(new), "languages")
