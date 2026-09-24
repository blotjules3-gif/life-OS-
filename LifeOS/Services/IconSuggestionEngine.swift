import Foundation

// MARK: - Moteur de suggestion d'icônes (Catalogue étendu 1 100+ symboles & Recherche multi-mots)

public enum IconSuggestionEngine {

    /// Liste de repli générale : 20 icônes favorites variées.
    public static let default20: [String] = [
        "drop.fill",
        "book.fill",
        "dumbbell.fill",
        "figure.run",
        "leaf.fill",
        "sun.max.fill",
        "moon.fill",
        "bed.double.fill",
        "pencil",
        "heart.fill",
        "cup.and.saucer.fill",
        "laptopcomputer",
        "flame.fill",
        "house.fill",
        "fork.knife",
        "eurosign.circle.fill",
        "checklist",
        "infinity",
        "target",
        "pawprint.fill"
    ]

    /// Mots vides exclus de la recherche sémantique multi-mots (FR + EN).
    private static let stopWords: Set<String> = [
        "le", "la", "les", "un", "une", "des", "du", "de", "d", "a", "au", "aux", "en",
        "pour", "sur", "avec", "sans", "dans", "mon", "ma", "mes", "ton", "ta", "tes",
        "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs", "et", "ou",
        "ce", "cet", "cette", "ces", "par", "se", "y", "the", "in", "on", "at", "to",
        "for", "with", "of", "and", "or", "a", "an", "is", "it", "my", "your"
    ]

    /// Catalogue complet d'icônes organisées par catégories (1 100+ symboles SF Symbols).
    public static let catalog: [(category: String, icons: [String])] = [
        ("Sport & Fitness", [
            "dumbbell.fill", "figure.strengthtraining.traditional", "figure.run",
            "figure.walk", "figure.outdoor.cycle", "figure.indoor.cycle",
            "figure.pool.swim", "figure.open.water.swim", "figure.boxing",
            "figure.kickboxing", "figure.martial.arts", "figure.yoga",
            "figure.pilates", "figure.cross.training", "figure.highintensity.intervaltraining",
            "figure.core.training", "figure.flexibility", "figure.cooldown",
            "figure.jumprope", "figure.stair.stepper", "figure.stairs",
            "figure.step.training", "figure.climbing", "figure.hiking",
            "figure.dance", "figure.socialdance", "figure.skateboarding",
            "figure.snowboarding", "figure.skiing.downhill", "figure.skiing.crosscountry",
            "figure.surfing", "figure.sailing", "figure.waterpolo",
            "figure.water.fitness", "figure.tennis", "figure.table.tennis",
            "figure.squash", "figure.badminton", "figure.basketball",
            "figure.rugby", "figure.volleyball", "figure.baseball",
            "figure.softball", "figure.golf", "figure.bowling",
            "figure.archery", "figure.fencing", "figure.handball",
            "figure.lacrosse", "figure.hockey", "figure.field.hockey",
            "figure.ice.hockey", "figure.cricket", "figure.curling",
            "figure.track.and.field", "figure.wrestling", "figure.taichi",
            "flame.fill", "bolt.heart.fill", "trophy.fill",
            "medal.fill", "timer", "stopwatch.fill",
            "shoe.2.fill", "sportscourt.fill", "lungs.fill",
            "baseball.fill", "basketball.fill", "tennisball.fill",
            "volleyball.fill", "cricket.ball.fill", "1.lane",
            "10.lane", "11.lane", "12.lane",
            "2.lane", "3.lane", "4.lane",
            "5.lane", "6.lane", "7.lane",
            "8.lane", "9.lane", "american.football",
            "american.football.circle", "american.football.circle.fill", "american.football.fill",
            "american.football.professional", "american.football.professional.circle", "american.football.professional.circle.fill",
            "american.football.professional.fill", "australian.football", "australian.football.circle",
            "australian.football.circle.fill", "australian.football.fill"
        ]),
        ("Santé & Vitalité", [
            "heart.fill", "heart.circle.fill", "heart.square.fill",
            "bolt.heart", "heart.text.square.fill", "cross.case.fill",
            "cross.fill", "cross.circle.fill", "pills.fill",
            "pills.circle.fill", "bandage.fill", "syringe.fill",
            "stethoscope", "thermometer.medium", "eye.fill",
            "eye.circle.fill", "ear.fill", "mouth.fill",
            "brain.head.profile", "brain.fill", "figure.walk.motion",
            "waveform.path.ecg", "waveform.path.ecg.rectangle.fill", "staroflife.fill",
            "shield.lefthalf.filled", "facemask.fill", "lungs.fill",
            "heart.slash.fill", "allergens", "allergens.fill",
            "apple.meditate", "apple.meditate.circle", "apple.meditate.circle.fill",
            "apple.meditate.square.stack", "apple.meditate.square.stack.fill", "bandage",
            "bed.double", "bed.double.badge.checkmark", "bed.double.badge.checkmark.fill",
            "bed.double.circle", "bed.double.circle.fill", "bed.double.fill",
            "blood.pressure.cuff", "blood.pressure.cuff.badge.gauge.with.needle", "blood.pressure.cuff.badge.gauge.with.needle.fill",
            "blood.pressure.cuff.fill", "bolt.heart.fill", "brain",
            "brain.filled.head.profile", "brain.head.profile.fill", "bubbles.and.sparkles",
            "bubbles.and.sparkles.fill", "chart.line.text.clipboard", "chart.line.text.clipboard.fill",
            "cross", "cross.case", "cross.case.circle",
            "cross.case.circle.fill", "cross.circle", "cross.vial",
            "cross.vial.fill", "ear", "ear.badge.checkmark",
            "ear.badge.waveform", "ear.trianglebadge.exclamationmark", "eye",
            "eye.circle", "eye.slash.fill", "eye.square",
            "eye.square.fill", "eye.trianglebadge.exclamationmark", "eye.trianglebadge.exclamationmark.fill",
            "facemask", "hearingdevice.and.signal.meter", "hearingdevice.and.signal.meter.fill",
            "hearingdevice.ear", "hearingdevice.ear.fill", "heart",
            "heart.badge.bolt", "heart.badge.bolt.fill", "heart.badge.bolt.slash.fill",
            "heart.circle", "heart.text.clipboard", "heart.text.clipboard.fill",
            "heart.text.square"
        ]),
        ("Nutrition & Repas", [
            "fork.knife", "fork.knife.circle.fill", "takeoutbag.and.cup.and.straw.fill",
            "birthday.cake.fill", "carrot.fill", "fish.circle.fill",
            "frying.pan.fill", "popcorn.fill"
        ]),
        ("Boissons & Hydratation", [
            "drop.fill", "drop.circle.fill", "waterbottle.fill",
            "cup.and.saucer.fill", "mug.fill", "wineglass.fill"
        ]),
        ("Sommeil & Nuit", [
            "bed.double.fill", "bed.double", "moon.fill",
            "moon.stars.fill", "moon.circle.fill", "moon.haze.fill",
            "sunset.fill", "sun.horizon.fill", "sunrise.fill"
        ]),
        ("Esprit & Méditation", [
            "figure.yoga", "leaf.fill", "leaf.circle.fill",
            "wind", "infinity", "sun.max.fill",
            "sun.min.fill", "brain.head.profile", "sparkles",
            "mountain.2.fill", "rainbow", "heart.circle.fill"
        ]),
        ("Productivité & Organisation", [
            "checklist", "list.bullet.clipboard.fill", "list.clipboard.fill",
            "folder.fill", "folder.badge.plus", "tray.full.fill",
            "tray.2.fill", "briefcase.fill", "hammer.fill",
            "wrench.and.screwdriver.fill", "screwdriver.fill", "ruler.fill",
            "scissors", "target", "chart.bar.fill",
            "calendar", "calendar.badge.clock", "calendar.badge.plus",
            "calendar.badge.checkmark", "clock.fill", "alarm.fill",
            "hourglass", "archivebox.fill", "pin.fill",
            "paperplane.fill", "paperclip", "link",
            "bell.fill", "bell.badge.fill", "1.calendar",
            "1.magnifyingglass", "10.calendar", "11.calendar",
            "12.calendar", "13.calendar", "14.calendar",
            "15.calendar", "16.calendar", "17.calendar",
            "18.calendar", "19.calendar", "2.calendar",
            "20.calendar", "21.calendar", "22.calendar",
            "23.calendar", "24.calendar", "25.calendar",
            "26.calendar", "27.calendar", "28.calendar",
            "29.calendar", "3.calendar", "30.calendar",
            "31.calendar", "4.calendar", "5.calendar",
            "6.calendar", "7.calendar", "8.calendar",
            "9.calendar", "air.conditioner.horizontal", "air.conditioner.horizontal.fill",
            "air.conditioner.vertical", "air.conditioner.vertical.fill", "air.purifier",
            "air.purifier.fill", "airpods.max", "alarm",
            "alarm.badge.exclamationmark", "alarm.badge.exclamationmark.fill", "alarm.badge.minus",
            "alarm.badge.minus.fill", "alarm.badge.xmark", "alarm.badge.xmark.fill",
            "alarm.slash.fill", "alarm.waves.left.and.right", "alarm.waves.left.and.right.fill",
            "american.football", "american.football.circle", "american.football.circle.fill",
            "american.football.fill", "american.football.professional", "american.football.professional.circle",
            "american.football.professional.circle.fill", "american.football.professional.fill", "amplifier",
            "antenna.radiowaves.left.and.right", "antenna.radiowaves.left.and.right.circle", "antenna.radiowaves.left.and.right.circle.fill"
        ]),
        ("Études, Lecture & Savoir", [
            "book.fill", "book.closed.fill", "books.vertical.fill",
            "bookmark.fill", "character.book.closed.fill", "graduationcap.fill",
            "pencil", "pencil.and.outline", "pencil.line",
            "highlighter", "backpack.fill", "globe.europe.africa.fill",
            "atom", "align.horizontal.center", "align.horizontal.center.fill",
            "align.horizontal.left", "align.horizontal.left.fill", "align.horizontal.right",
            "align.horizontal.right.fill", "align.vertical.bottom", "align.vertical.bottom.fill",
            "align.vertical.center", "align.vertical.center.fill", "align.vertical.top",
            "align.vertical.top.fill", "arrow.left.and.right.text.vertical", "arrow.trianglehead.left.and.right.righttriangle.left.righttriangle.right",
            "arrow.trianglehead.left.and.right.righttriangle.left.righttriangle.right.fill", "arrow.trianglehead.up.and.down.righttriangle.up.righttriangle.down", "arrow.trianglehead.up.and.down.righttriangle.up.righttriangle.down.fill",
            "arrow.up.and.down.text.horizontal", "aspectratio", "aspectratio.fill",
            "bandage", "bandage.fill", "beziercurve",
            "bold", "bold.italic.underline", "bold.underline",
            "bubble.and.pencil", "camera.filters", "character",
            "character.bn", "character.circle", "character.circle.bn",
            "character.circle.fill", "character.circle.fill.bn", "character.circle.fill.gu",
            "character.circle.fill.kn", "character.circle.fill.ml", "character.circle.fill.mni",
            "character.circle.fill.mr", "character.circle.fill.or", "character.circle.fill.pa",
            "character.circle.fill.sat", "character.circle.fill.si", "character.circle.fill.ta",
            "character.circle.fill.te", "character.circle.gu", "character.circle.kn",
            "character.circle.ml", "character.circle.mni", "character.circle.mr",
            "character.circle.or", "character.circle.pa", "character.circle.sat",
            "character.circle.si", "character.circle.ta", "character.circle.te",
            "character.cursor.ibeam", "character.duployan", "character.gu",
            "character.kn", "character.magnify", "character.magnify.bn",
            "character.magnify.gu", "character.magnify.kn", "character.magnify.ml",
            "character.magnify.mni", "character.magnify.mr"
        ]),
        ("Tech & Informatique", [
            "laptopcomputer", "desktopcomputer", "keyboard.fill",
            "display", "server.rack", "cpu.fill",
            "memorychip.fill", "antenna.radiowaves.left.and.right", "wifi",
            "network", "bolt.fill", "bolt.badge.automatic.fill",
            "power", "externaldrive.fill", "cable.connector",
            "iphone", "ipad", "applewatch",
            "4k.tv", "4k.tv.fill", "airpod.gen3.left",
            "airpod.gen3.right", "airpod.left", "airpod.right",
            "airpods", "airpods.chargingcase", "airpods.chargingcase.fill",
            "airpods.chargingcase.wireless", "airpods.chargingcase.wireless.fill", "airpods.gen3",
            "airpods.gen3.chargingcase.wireless", "airpods.gen3.chargingcase.wireless.fill", "airpods.gen4",
            "airpods.gen4.chargingcase.wireless", "airpods.gen4.chargingcase.wireless.fill", "airpods.gen4.left",
            "airpods.gen4.right", "airpods.max", "airpods.pro",
            "airpods.pro.chargingcase.wireless", "airpods.pro.chargingcase.wireless.fill", "airpods.pro.chargingcase.wireless.radiowaves.left.and.right",
            "airpods.pro.chargingcase.wireless.radiowaves.left.and.right.fill", "airpods.pro.gen1", "airpods.pro.gen1.chargingcase.wireless",
            "airpods.pro.gen1.chargingcase.wireless.fill", "airpods.pro.gen1.chargingcase.wireless.radiowaves.left.and.right", "airpods.pro.gen1.chargingcase.wireless.radiowaves.left.and.right.fill",
            "airpods.pro.gen1.left", "airpods.pro.gen1.right", "airpods.pro.gen3",
            "airpods.pro.gen3.chargingcase.wireless", "airpods.pro.gen3.chargingcase.wireless.fill", "airpods.pro.gen3.chargingcase.wireless.radiowaves.left.and.right",
            "airpods.pro.gen3.chargingcase.wireless.radiowaves.left.and.right.fill", "airpods.pro.gen3.left", "airpods.pro.gen3.right",
            "airpods.pro.left", "airpods.pro.right", "airport.express",
            "airport.extreme", "airport.extreme.tower", "airtag",
            "airtag.fill", "airtag.radiowaves.forward", "airtag.radiowaves.forward.fill",
            "applepencil", "applepencil.adapter.usb.c", "applepencil.adapter.usb.c.fill",
            "applepencil.and.scribble", "applepencil.doubletap", "applepencil.gen1",
            "applepencil.gen2", "applepencil.hover", "applepencil.squeeze",
            "applepencil.tip", "appletv", "appletv.badge.checkmark",
            "appletv.badge.checkmark.fill", "appletv.badge.exclamationmark", "appletv.badge.exclamationmark.fill",
            "appletv.fill", "appletvremote.gen1", "appletvremote.gen1.fill",
            "appletvremote.gen2"
        ]),
        ("Finances & Argent", [
            "eurosign.circle.fill", "dollarsign.circle.fill", "sterlingsign.circle.fill",
            "yensign.circle.fill", "bitcoinsign.circle.fill", "creditcard.fill",
            "banknote.fill", "cart.fill", "bag.fill",
            "basket.fill", "gift.fill", "tag.fill",
            "wallet.pass.fill", "percent", "australiandollarsign",
            "australiandollarsign.arrow.trianglehead.counterclockwise.rotate.90", "australiandollarsign.building.classical", "australiandollarsign.building.classical.fill",
            "australiandollarsign.circle", "australiandollarsign.circle.fill", "australiandollarsign.gauge.chart.lefthalf.righthalf",
            "australiandollarsign.gauge.chart.leftthird.topthird.rightthird", "australiandollarsign.ring", "australiandollarsign.ring.dashed",
            "australiandollarsign.square", "australiandollarsign.square.fill", "australsign",
            "australsign.arrow.trianglehead.counterclockwise.rotate.90", "australsign.building.classical", "australsign.building.classical.fill",
            "australsign.circle", "australsign.circle.fill", "australsign.gauge.chart.lefthalf.righthalf",
            "australsign.gauge.chart.leftthird.topthird.rightthird", "australsign.ring", "australsign.ring.dashed",
            "australsign.square", "australsign.square.fill", "bag",
            "bag.badge.minus", "bag.badge.plus", "bag.badge.questionmark",
            "bag.circle", "bag.circle.fill", "bag.fill.badge.minus",
            "bag.fill.badge.plus", "bag.fill.badge.questionmark", "bahtsign",
            "bahtsign.arrow.trianglehead.counterclockwise.rotate.90", "bahtsign.building.classical", "bahtsign.building.classical.fill",
            "bahtsign.circle", "bahtsign.circle.fill", "bahtsign.gauge.chart.lefthalf.righthalf",
            "bahtsign.gauge.chart.leftthird.topthird.rightthird", "bahtsign.ring", "bahtsign.ring.dashed",
            "bahtsign.square", "bahtsign.square.fill", "banknote",
            "basket", "bitcoinsign", "bitcoinsign.arrow.trianglehead.counterclockwise.rotate.90",
            "bitcoinsign.building.classical", "bitcoinsign.building.classical.fill", "bitcoinsign.circle",
            "bitcoinsign.gauge.chart.lefthalf.righthalf", "bitcoinsign.gauge.chart.leftthird.topthird.rightthird", "bitcoinsign.ring",
            "bitcoinsign.ring.dashed", "bitcoinsign.square", "bitcoinsign.square.fill",
            "brazilianrealsign", "brazilianrealsign.arrow.trianglehead.counterclockwise.rotate.90", "brazilianrealsign.building.classical",
            "brazilianrealsign.building.classical.fill", "brazilianrealsign.circle", "brazilianrealsign.circle.fill",
            "brazilianrealsign.gauge.chart.lefthalf.righthalf", "brazilianrealsign.gauge.chart.leftthird.topthird.rightthird", "brazilianrealsign.ring",
            "brazilianrealsign.ring.dashed", "brazilianrealsign.square", "brazilianrealsign.square.fill",
            "cart"
        ]),
        ("Maison & Quotidien", [
            "house.fill", "building.2.fill", "building.fill",
            "door.left.hand.closed", "door.left.hand.open", "key.fill",
            "lock.fill", "lock.open.fill", "paintbrush.fill",
            "paintpalette.fill", "bubbles.and.sparkles.fill", "trash.fill",
            "lightbulb.fill", "lamp.floor.fill", "shower.fill",
            "bathtub.fill", "sofa.fill", "fan.fill",
            "washer.fill", "air.conditioner.horizontal", "air.conditioner.horizontal.fill",
            "air.conditioner.vertical", "air.conditioner.vertical.fill", "air.purifier",
            "air.purifier.fill", "apple.homekit", "australiandollarsign.gauge.chart.lefthalf.righthalf",
            "australiandollarsign.gauge.chart.leftthird.topthird.rightthird", "australiandollarsign.ring", "australiandollarsign.ring.dashed",
            "australsign.gauge.chart.lefthalf.righthalf", "australsign.gauge.chart.leftthird.topthird.rightthird", "australsign.ring",
            "australsign.ring.dashed", "av.remote", "av.remote.fill",
            "bahtsign.gauge.chart.lefthalf.righthalf", "bahtsign.gauge.chart.leftthird.topthird.rightthird", "bahtsign.ring",
            "bahtsign.ring.dashed", "balloon", "balloon.2",
            "balloon.2.fill", "balloon.fill", "bathtub",
            "bed.double", "bed.double.badge.checkmark", "bed.double.badge.checkmark.fill",
            "bed.double.circle", "bed.double.circle.fill", "bed.double.fill",
            "bitcoinsign.gauge.chart.lefthalf.righthalf", "bitcoinsign.gauge.chart.leftthird.topthird.rightthird", "bitcoinsign.ring",
            "bitcoinsign.ring.dashed", "blinds.horizontal.closed", "blinds.horizontal.open",
            "blinds.vertical.closed", "blinds.vertical.open", "brazilianrealsign.gauge.chart.lefthalf.righthalf",
            "brazilianrealsign.gauge.chart.leftthird.topthird.rightthird", "brazilianrealsign.ring", "brazilianrealsign.ring.dashed",
            "button.programmable", "button.programmable.square", "button.programmable.square.fill",
            "cabinet", "cabinet.fill", "carbon.dioxide.cloud",
            "carbon.dioxide.cloud.fill", "carbon.monoxide.cloud", "carbon.monoxide.cloud.fill",
            "cedisign.gauge.chart.lefthalf.righthalf", "cedisign.gauge.chart.leftthird.topthird.rightthird", "cedisign.ring",
            "cedisign.ring.dashed", "centsign.gauge.chart.lefthalf.righthalf", "centsign.gauge.chart.leftthird.topthird.rightthird",
            "centsign.ring", "centsign.ring.dashed"
        ]),
        ("Nature & Écologie", [
            "tree.fill", "drop.circle.fill", "flame.circle.fill",
            "mountain.2.fill", "sun.rain.fill", "cloud.sun.rain.fill",
            "cloud.bolt.rain.fill", "cloud.snow.fill", "snowflake",
            "thermometer.snowflake", "cloud.fill", "cloud.rain.fill",
            "cloud.sun.fill", "allergens", "allergens.fill",
            "ant", "ant.circle", "ant.circle.fill",
            "ant.fill", "apple.meditate", "apple.meditate.circle",
            "apple.meditate.circle.fill", "apple.meditate.square.stack", "apple.meditate.square.stack.fill",
            "atom", "bird", "bird.circle",
            "bird.circle.fill", "bird.fill", "bolt",
            "bolt.badge.automatic", "bolt.badge.automatic.fill", "bolt.badge.checkmark",
            "bolt.badge.checkmark.fill", "bolt.badge.clock", "bolt.badge.clock.fill",
            "bolt.badge.xmark", "bolt.badge.xmark.fill", "bolt.circle",
            "bolt.circle.fill", "bolt.fill", "bolt.shield",
            "bolt.shield.fill", "bolt.slash.circle", "bolt.slash.circle.fill",
            "bolt.slash.fill", "bolt.square", "bolt.square.fill",
            "bolt.trianglebadge.exclamationmark", "bolt.trianglebadge.exclamationmark.fill", "camera.macro",
            "camera.macro.circle", "camera.macro.circle.fill", "camera.macro.slash.circle",
            "camera.macro.slash.circle.fill", "carrot", "carrot.fill",
            "cat", "cat.circle", "cat.circle.fill",
            "cat.fill", "cloud", "cloud.bolt",
            "cloud.bolt.circle", "cloud.bolt.circle.fill", "cloud.bolt.fill",
            "cloud.bolt.rain", "cloud.bolt.rain.circle", "cloud.bolt.rain.circle.fill",
            "cloud.circle", "cloud.circle.fill", "cloud.drizzle",
            "cloud.drizzle.circle", "cloud.drizzle.circle.fill", "cloud.drizzle.fill"
        ]),
        ("Météo & Espace", [
            "sun.max.fill", "cloud.sun.fill", "moon.stars.fill",
            "snowflake", "sparkles", "aqi.high",
            "aqi.low", "aqi.medium", "carbon.dioxide.cloud",
            "carbon.dioxide.cloud.fill", "carbon.monoxide.cloud", "carbon.monoxide.cloud.fill",
            "cloud", "cloud.bolt", "cloud.bolt.circle",
            "cloud.bolt.circle.fill", "cloud.bolt.fill", "cloud.bolt.rain",
            "cloud.bolt.rain.circle", "cloud.bolt.rain.circle.fill", "cloud.bolt.rain.fill",
            "cloud.circle", "cloud.circle.fill", "cloud.drizzle",
            "cloud.drizzle.circle", "cloud.drizzle.circle.fill", "cloud.drizzle.fill",
            "cloud.fill", "cloud.fog", "cloud.fog.circle",
            "cloud.fog.circle.fill", "cloud.fog.fill", "cloud.hail",
            "cloud.hail.circle", "cloud.hail.circle.fill", "cloud.hail.fill",
            "cloud.heavyrain", "cloud.heavyrain.circle", "cloud.heavyrain.circle.fill",
            "cloud.heavyrain.fill", "cloud.moon", "cloud.moon.bolt",
            "cloud.moon.bolt.circle", "cloud.moon.bolt.circle.fill", "cloud.moon.bolt.fill",
            "cloud.moon.circle", "cloud.moon.circle.fill", "cloud.moon.fill",
            "cloud.moon.rain", "cloud.moon.rain.circle", "cloud.moon.rain.circle.fill",
            "cloud.moon.rain.fill", "cloud.rain", "cloud.rain.circle",
            "cloud.rain.circle.fill", "cloud.rain.fill", "cloud.rainbow.crop",
            "cloud.rainbow.crop.fill", "cloud.sleet", "cloud.sleet.circle",
            "cloud.sleet.circle.fill", "cloud.sleet.fill", "cloud.snow",
            "cloud.snow.circle", "cloud.snow.circle.fill", "cloud.snow.fill",
            "cloud.sun", "cloud.sun.bolt", "cloud.sun.bolt.circle",
            "cloud.sun.bolt.circle.fill", "cloud.sun.bolt.fill", "cloud.sun.circle",
            "cloud.sun.circle.fill", "cloud.sun.rain", "cloud.sun.rain.circle"
        ]),
        ("Animaux & Compagnons", [
            "pawprint.fill", "dog.fill", "cat.fill",
            "bird.fill", "fish.fill", "hare.fill",
            "tortoise.fill", "lizard.fill"
        ]),
        ("Social, Famille & Relations", [
            "person.fill", "person.2.fill", "person.3.fill",
            "heart.square.fill", "person.crop.circle.fill", "message.fill",
            "bubble.left.and.bubble.right.fill", "phone.fill", "envelope.fill",
            "hand.thumbsup.fill", "hand.wave.fill", "accessibility",
            "accessibility.badge.arrow.up.right", "accessibility.fill", "arrow.down.left.video",
            "arrow.down.left.video.fill", "arrow.down.message", "arrow.down.message.fill",
            "arrow.up.and.person.rectangle.portrait", "arrow.up.and.person.rectangle.turn.left", "arrow.up.and.person.rectangle.turn.right",
            "arrow.up.message", "arrow.up.message.fill", "arrow.up.right.video",
            "arrow.up.right.video.fill", "backward.bubble", "backward.bubble.fill",
            "brain", "brain.fill", "brain.filled.head.profile",
            "brain.head.profile", "brain.head.profile.fill", "bubble",
            "bubble.and.pencil", "bubble.circle", "bubble.circle.fill",
            "bubble.fill", "bubble.left", "bubble.left.and.bubble.right",
            "bubble.left.and.exclamationmark.bubble.right", "bubble.left.and.exclamationmark.bubble.right.fill", "bubble.left.and.heart.bubble.right",
            "bubble.left.and.heart.bubble.right.fill", "bubble.left.and.text.bubble.right", "bubble.left.and.text.bubble.right.fill",
            "bubble.left.circle", "bubble.left.circle.fill", "bubble.left.fill",
            "bubble.middle.bottom", "bubble.middle.bottom.fill", "bubble.middle.top",
            "bubble.middle.top.fill", "bubble.right", "bubble.right.circle",
            "bubble.right.circle.fill", "bubble.right.fill", "calendar.and.person",
            "captions.bubble", "captions.bubble.fill", "character.bubble",
            "character.bubble.bn", "character.bubble.fill", "character.bubble.fill.bn",
            "character.bubble.fill.gu", "character.bubble.fill.kn", "character.bubble.fill.ml",
            "character.bubble.fill.mni", "character.bubble.fill.mr", "character.bubble.fill.or",
            "character.bubble.fill.pa", "character.bubble.fill.sat", "character.bubble.fill.si",
            "character.bubble.fill.ta", "character.bubble.fill.te", "character.bubble.gu",
            "character.bubble.kn", "character.bubble.ml", "character.bubble.mni",
            "character.bubble.mr", "character.bubble.or"
        ]),
        ("Musique & Audio", [
            "headphones", "guitars.fill", "speaker.wave.3.fill",
            "waveform", "radio.fill", "10.arrow.trianglehead.clockwise",
            "10.arrow.trianglehead.counterclockwise", "15.arrow.trianglehead.clockwise", "15.arrow.trianglehead.counterclockwise",
            "30.arrow.trianglehead.clockwise", "30.arrow.trianglehead.counterclockwise", "45.arrow.trianglehead.clockwise",
            "45.arrow.trianglehead.counterclockwise", "5.arrow.trianglehead.clockwise", "5.arrow.trianglehead.counterclockwise",
            "60.arrow.trianglehead.clockwise", "60.arrow.trianglehead.counterclockwise", "75.arrow.trianglehead.clockwise",
            "75.arrow.trianglehead.counterclockwise", "90.arrow.trianglehead.clockwise", "90.arrow.trianglehead.counterclockwise",
            "arrow.trianglehead.clockwise", "arrow.trianglehead.counterclockwise", "arrow.trianglehead.rectanglepath",
            "backward", "backward.circle", "backward.circle.fill",
            "backward.end", "backward.end.alt", "backward.end.alt.fill",
            "backward.end.circle", "backward.end.circle.fill", "backward.end.fill",
            "backward.fill", "backward.frame", "backward.frame.fill",
            "checkmark.arrow.trianglehead.counterclockwise", "forward", "forward.circle",
            "forward.circle.fill", "forward.end", "forward.end.alt",
            "forward.end.alt.fill", "forward.end.circle", "forward.end.circle.fill",
            "forward.end.fill", "forward.fill", "forward.frame",
            "forward.frame.fill", "house.badge.exclamationmark", "house.badge.exclamationmark.fill",
            "infinity", "infinity.circle", "infinity.circle.fill",
            "minus.arrow.trianglehead.counterclockwise", "music.note.house", "music.note.house.fill",
            "pause", "pause.circle", "pause.circle.fill",
            "pause.fill", "pause.rectangle", "pause.rectangle.fill",
            "phone.pause", "phone.pause.circle"
        ]),
        ("Arts, Photo & Divertissement", [
            "camera.fill", "video.fill", "theatermasks.fill",
            "ticket.fill", "film.fill", "dice.fill",
            "gamecontroller.fill", "tv.fill", "puzzlepiece.fill",
            "a.circle", "a.circle.fill", "arcade.stick",
            "arcade.stick.and.arrow.down", "arcade.stick.and.arrow.left", "arcade.stick.and.arrow.left.and.arrow.right.outward",
            "arcade.stick.and.arrow.right", "arcade.stick.and.arrow.up", "arcade.stick.and.arrow.up.and.arrow.down",
            "arcade.stick.console", "arcade.stick.console.fill", "arrow.down.backward.and.arrow.up.forward",
            "arrow.down.backward.and.arrow.up.forward.circle", "arrow.down.backward.and.arrow.up.forward.circle.fill", "arrow.down.backward.and.arrow.up.forward.square",
            "arrow.down.backward.and.arrow.up.forward.square.fill", "arrow.down.forward.and.arrow.up.backward", "arrow.down.forward.and.arrow.up.backward.circle",
            "arrow.down.forward.and.arrow.up.backward.circle.fill", "arrow.down.forward.and.arrow.up.backward.square", "arrow.down.forward.and.arrow.up.backward.square.fill",
            "arrow.down.left.and.arrow.up.right", "arrow.down.left.and.arrow.up.right.circle", "arrow.down.left.and.arrow.up.right.circle.fill",
            "arrow.down.left.and.arrow.up.right.square", "arrow.down.left.and.arrow.up.right.square.fill", "arrow.down.right.and.arrow.up.left",
            "arrow.down.right.and.arrow.up.left.circle", "arrow.down.right.and.arrow.up.left.circle.fill", "arrow.down.right.and.arrow.up.left.square",
            "arrow.down.right.and.arrow.up.left.square.fill", "arrow.trianglehead.2.clockwise.rotate.90", "arrow.trianglehead.2.clockwise.rotate.90.camera",
            "arrow.trianglehead.2.clockwise.rotate.90.camera.fill", "arrow.trianglehead.2.clockwise.rotate.90.circle", "arrow.trianglehead.2.clockwise.rotate.90.circle.fill",
            "arrow.trianglehead.left.and.right.righttriangle.left.righttriangle.right", "arrow.trianglehead.left.and.right.righttriangle.left.righttriangle.right.fill", "arrow.trianglehead.up.and.down.righttriangle.up.righttriangle.down",
            "arrow.trianglehead.up.and.down.righttriangle.up.righttriangle.down.fill", "arrow.up.backward.and.arrow.down.forward", "arrow.up.backward.and.arrow.down.forward.circle",
            "arrow.up.backward.and.arrow.down.forward.circle.fill", "arrow.up.backward.and.arrow.down.forward.square", "arrow.up.backward.and.arrow.down.forward.square.fill",
            "arrow.up.forward.and.arrow.down.backward", "arrow.up.forward.and.arrow.down.backward.circle", "arrow.up.forward.and.arrow.down.backward.circle.fill",
            "arrow.up.forward.and.arrow.down.backward.square", "arrow.up.forward.and.arrow.down.backward.square.fill", "arrow.up.left.and.arrow.down.right",
            "arrow.up.left.and.arrow.down.right.circle", "arrow.up.left.and.arrow.down.right.circle.fill", "arrow.up.left.and.arrow.down.right.square",
            "arrow.up.left.and.arrow.down.right.square.fill", "arrow.up.right.and.arrow.down.left", "arrow.up.right.and.arrow.down.left.circle",
            "arrow.up.right.and.arrow.down.left.circle.fill", "arrow.up.right.and.arrow.down.left.square", "arrow.up.right.and.arrow.down.left.square.fill",
            "arrowkeys", "arrowkeys.down.filled", "arrowkeys.fill",
            "arrowkeys.left.filled", "arrowkeys.right.filled", "arrowkeys.up.filled"
        ]),
        ("Voyage, Transport & Plein air", [
            "car.fill", "bicycle", "fuelpump.fill",
            "airplane", "airplane.departure", "airplane.arrival",
            "tram.fill", "bus.fill", "train.side.front.car",
            "ferry.fill", "sailboat.fill", "map.fill",
            "location.fill", "compass.drawing", "binoculars.fill",
            "tent.fill", "suitcase.fill", "1.brakesignal",
            "2.brakesignal", "2h", "2h.circle",
            "2h.circle.fill", "4a", "4a.circle",
            "4a.circle.fill", "4h", "4h.circle",
            "4h.circle.fill", "4l", "4l.circle",
            "4l.circle.fill", "abs", "abs.brakesignal",
            "abs.circle", "abs.circle.fill", "air.car.side",
            "air.car.side.fill", "air.conditioner", "air.convertible.side",
            "air.convertible.side.fill", "air.pickup.side", "air.pickup.side.fill",
            "air.suv.side", "air.suv.side.fill", "airplane.circle",
            "airplane.circle.fill", "airplane.cloud", "airplane.landed",
            "airplane.path.dotted", "airplane.ticket", "airplane.ticket.fill",
            "airplane.up.forward", "airplane.up.forward.app", "airplane.up.forward.app.fill",
            "airplane.up.right", "airplane.up.right.app", "airplane.up.right.app.fill",
            "airplaneseat", "app.connected.to.app.below.fill", "arrow.right.filled.filter.arrow.right",
            "arrow.trianglehead.branch", "arrow.trianglehead.merge", "arrow.trianglehead.pull",
            "arrow.trianglehead.swap", "arrow.trianglehead.turn.up.right.circle", "arrow.trianglehead.turn.up.right.circle.fill",
            "arrow.trianglehead.turn.up.right.diamond", "arrow.trianglehead.turn.up.right.diamond.fill", "arrow.turn.down.left",
            "arrow.turn.down.right", "arrow.turn.left.down", "arrow.turn.left.up",
            "arrow.turn.right.down", "arrow.turn.right.up", "arrow.turn.up.left",
            "arrow.turn.up.right", "arrow.up.and.down.and.arrow.left.and.right", "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left",
            "arrowshape.backward", "arrowshape.backward.circle", "arrowshape.backward.circle.fill",
            "arrowshape.backward.fill", "arrowshape.forward", "arrowshape.forward.circle",
            "arrowshape.forward.circle.fill", "arrowshape.forward.fill", "arrowshape.left",
            "arrowshape.left.arrowshape.right", "arrowshape.left.arrowshape.right.fill", "arrowshape.left.circle"
        ]),
        ("Soins personnels & Mode", [
            "tshirt.fill", "shoe.fill", "eyeglasses",
            "comb.fill", "crown.fill", "sparkle"
        ]),
        ("Badges, Symboles & Géométrie", [
            "infinity", "star.fill", "star.circle.fill",
            "flag.fill", "shield.fill", "checkmark.seal.fill",
            "rosette", "checkmark.circle.fill", "exclamationmark.triangle.fill",
            "app", "app.fill", "bubble.left.and.exclamationmark.bubble.right",
            "bubble.left.and.exclamationmark.bubble.right.fill", "button.angledbottom.horizontal.left", "button.angledbottom.horizontal.left.fill",
            "button.angledbottom.horizontal.right", "button.angledbottom.horizontal.right.fill", "button.angledtop.vertical.left",
            "button.angledtop.vertical.left.fill", "button.angledtop.vertical.right", "button.angledtop.vertical.right.fill",
            "button.horizontal", "button.horizontal.fill", "button.roundedbottom.horizontal",
            "button.roundedbottom.horizontal.fill", "button.roundedtop.horizontal", "button.roundedtop.horizontal.fill",
            "capsule", "capsule.fill", "capsule.portrait",
            "capsule.portrait.fill", "checkmark", "checkmark.circle",
            "checkmark.circle.badge.plus", "checkmark.circle.badge.plus.fill", "checkmark.circle.badge.questionmark",
            "checkmark.circle.badge.questionmark.fill", "checkmark.circle.badge.xmark", "checkmark.circle.badge.xmark.fill",
            "checkmark.circle.dotted", "checkmark.circle.trianglebadge.exclamationmark", "checkmark.circle.trianglebadge.exclamationmark.fill",
            "checkmark.diamond", "checkmark.diamond.fill", "checkmark.icloud",
            "checkmark.icloud.fill", "checkmark.message", "checkmark.message.fill",
            "checkmark.rectangle", "checkmark.rectangle.fill", "checkmark.rectangle.portrait",
            "checkmark.rectangle.portrait.fill", "checkmark.seal", "checkmark.shield",
            "checkmark.shield.fill", "checkmark.square", "checkmark.square.fill",
            "circle", "circle.fill", "diamond",
            "diamond.fill", "envelope.and.hand.raised", "envelope.and.hand.raised.fill",
            "envelope.badge.shield.half.filled", "envelope.badge.shield.half.filled.fill", "exclamationmark.bubble",
            "exclamationmark.bubble.circle", "exclamationmark.bubble.circle.fill", "exclamationmark.bubble.fill",
            "exclamationmark.lock"
        ]),
    ]

    /// Table de correspondance de mots-clés bilingues (FR / EN) avec priorité ordonnée.
    private static let keywordMap: [(keywords: [String], icons: [String])] = [
        (
            ["workout", "sport", "gym", "muscu", "musculation", "fitness", "biceps", "train", "push", "pull", "legs", "fonte", "halter", "alter", "body", "salle", "abdos", "pompes", "squat", "crossfit", "cardio", "hiit"],
            ["dumbbell.fill", "figure.strengthtraining.traditional", "flame.fill", "trophy.fill", "bolt.heart.fill", "figure.cross.training", "timer"]
        ),
        (
            ["run", "course", "courir", "footing", "jogging", "marathon", "sprint", "foulée", "running", "trail"],
            ["figure.run", "shoe.2.fill", "flame.fill", "heart.fill", "timer", "stopwatch.fill"]
        ),
        (
            ["walk", "marche", "marcher", "pas", "steps", "balade", "randonnee", "rando", "hike", "promenade"],
            ["figure.walk", "shoe.2.fill", "leaf.fill", "figure.climbing", "map.fill"]
        ),
        (
            ["velo", "bike", "cycling", "cyclisme", "bicyclette", "vtt", "pedaler", "tour"],
            ["figure.outdoor.cycle", "bicycle", "heart.fill", "timer"]
        ),
        (
            ["boxe", "boxing", "combat", "fight", "mma", "karate", "judo", "kickboxing"],
            ["figure.boxing", "flame.fill", "trophy.fill"]
        ),
        (
            ["swim", "nage", "natation", "piscine", "pool", "baignade", "crawl"],
            ["figure.pool.swim", "drop.fill", "waterbottle.fill"]
        ),
        (
            ["eau", "water", "boire", "drink", "hydrat", "hydratation", "bouteille", "verre", "litre"],
            ["drop.fill", "waterbottle.fill", "cup.and.saucer.fill", "mug.fill"]
        ),
        (
            ["read", "lire", "livre", "book", "lecture", "roman", "manga", "page", "bouquin", "bd", "chapitre"],
            ["book.fill", "books.vertical.fill", "bookmark.fill", "character.book.closed.fill", "doc.text.fill"]
        ),
        (
            ["etude", "study", "cours", "ecole", "reviser", "revision", "learn", "apprendre", "examen", "devoir", "diplome", "universite", "prepa", "lecon"],
            ["graduationcap.fill", "book.fill", "pencil", "pencil.and.outline", "brain.head.profile"]
        ),
        (
            ["ecrire", "write", "journal", "note", "noter", "pencil", "pen", "rediger", "stylo", "cahier"],
            ["pencil", "pencil.and.outline", "doc.text.fill", "bookmark.fill"]
        ),
        (
            ["sleep", "dormir", "sommeil", "bed", "lit", "sieste", "nap", "repos", "nuit", "night", "coucher", "reveil"],
            ["bed.double.fill", "moon.fill", "moon.stars.fill", "zzz", "powersleep"]
        ),
        (
            ["medit", "zen", "respir", "breathe", "calm", "relax", "paix", "yoga", "souffle", "conscience", "detente", "serenite"],
            ["figure.yoga", "leaf.fill", "wind", "infinity", "sun.max.fill", "heart.circle.fill"]
        ),
        (
            ["clean", "menage", "ranger", "tidy", "maison", "house", "nettoy", "aspirat", "vaisselle", "lessive", "laver", "ordre"],
            ["house.fill", "bubbles.and.sparkles.fill", "trash.fill", "paintbrush.fill", "infinity"]
        ),
        (
            ["code", "dev", "program", "work", "travail", "boulot", "ordi", "computer", "bureau", "job", "swift", "python", "informatique", "projet"],
            ["laptopcomputer", "terminal.fill", "desktopcomputer", "keyboard.fill", "briefcase.fill", "checklist"]
        ),
        (
            ["argent", "money", "budget", "econom", "salaire", "invest", "bourse", "finance", "crypto", "banque", "epargne", "facture", "payer", "achat", "vendre", "carte"],
            ["eurosign.circle.fill", "dollarsign.circle.fill", "banknote.fill", "creditcard.fill", "chart.line.uptrend.xyaxis", "bitcoinsign.circle.fill"]
        ),
        (
            ["manger", "eat", "food", "cook", "cuisine", "nutrition", "repas", "diet", "diner", "dejeuner", "dej", "petit-dej", "recette", "jeune", "calorie"],
            ["fork.knife", "carrot.fill", "takeoutbag.and.cup.and.straw.fill", "apple.logo", "cup.and.saucer.fill", "frying.pan.fill"]
        ),
        (
            ["cafe", "coffee", "the", "tea", "espresso", "latte", "tisane"],
            ["cup.and.saucer.fill", "mug.fill"]
        ),
        (
            ["chien", "chat", "dog", "cat", "pet", "animal", "animaux", "veterinaire", "croquette", "promener", "poisson", "oiseau"],
            ["pawprint.fill", "dog.fill", "cat.fill", "bird.fill", "fish.fill"]
        ),
        (
            ["soleil", "sun", "matin", "morning", "reveil", "lever", "aube"],
            ["sun.max.fill", "sun.horizon.fill", "sunrise.fill", "infinity"]
        ),
        (
            ["voiture", "car", "conduire", "drive", "permis", "essence", "trajet", "route", "moto", "train", "metro", "bus", "avion", "voyage"],
            ["car.fill", "fuelpump.fill", "key.fill", "airplane", "tram.fill"]
        ),
        (
            ["musique", "music", "guitare", "piano", "chanter", "song", "audio", "ecouteur", "casque", "playlist", "morceau"],
            ["music.note", "guitars.fill", "headphones", "speaker.wave.3.fill"]
        ),
        (
            ["appeler", "call", "famille", "amis", "friends", "message", "sms", "maman", "papa", "parent", "enfant", "partager", "amour", "couple"],
            ["phone.fill", "message.fill", "envelope.fill", "person.2.fill", "heart.fill"]
        )
    ]

    /// Normalise une chaîne de recherche (minuscule, sans accents, espaces condensés).
    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Découpe une phrase en mots-clés utiles (tokens filtrés des mots vides).
    public static func tokenize(_ text: String) -> [String] {
        let clean = normalize(text)
        let rawTokens = clean.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return rawTokens.filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    /// Recherche intelligente multi-mots sur l'ensemble du catalogue avec score de pertinence.
    public static func search(query: String, limit: Int = 100) -> [String] {
        let clean = normalize(query)
        guard !clean.isEmpty else { return [] }

        let queryTokens = tokenize(clean)
        var scores: [String: Int] = [:]
        var order: [String] = []

        func addScore(_ icon: String, points: Int) {
            if scores[icon] == nil {
                order.append(icon)
            }
            scores[icon, default: 0] += points
        }

        // 1. Recherche par dictionnaire sémantique avec support multi-mots
        for entry in keywordMap {
            var entryScore = 0

            // Correspondance sur la phrase complète
            if clean.count >= 3 && entry.keywords.contains(where: { clean.contains($0) || $0.contains(clean) }) {
                entryScore += 100
            }

            // Correspondance par mot découpé
            var tokenHits = 0
            for token in queryTokens {
                let matches = entry.keywords.contains { kw in
                    if token == kw { return true }
                    if token.count >= 3 && kw.count >= 3 && (token.hasPrefix(kw) || kw.hasPrefix(token)) { return true }
                    if token.count >= 4 && kw.contains(token) { return true }
                    return false
                }
                if matches { tokenHits += 1 }
            }

            if tokenHits > 0 {
                entryScore += tokenHits * 50 + (tokenHits > 1 ? 60 : 0)
                for (idx, icon) in entry.icons.enumerated() {
                    let posBonus = max(0, 20 - idx * 2)
                    addScore(icon, points: entryScore + posBonus)
                }
            }
        }

        // 2. Recherche directe sur les noms des icônes dans tout le catalogue
        for (_, group) in catalog {
            for icon in group {
                let cleanIcon = normalize(icon.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "fill", with: ""))
                let iconWords = cleanIcon.split(separator: " ").map(String.init)

                if cleanIcon.contains(clean) {
                    addScore(icon, points: 70)
                }

                var hits = 0
                for token in queryTokens {
                    if iconWords.contains(token) {
                        hits += 1
                    } else if cleanIcon.contains(token) {
                        hits += 1
                    }
                }
                if hits > 0 {
                    addScore(icon, points: hits * 35 + (hits > 1 ? 40 : 0))
                }
            }
        }

        // Tri par score décroissant, conservant l'ordre d'apparition en cas d'égalité
        let sorted = order.sorted { a, b in
            let sa = scores[a] ?? 0
            let sb = scores[b] ?? 0
            return sa > sb
        }

        return Array(sorted.prefix(limit))
    }

    /// Génère exactement `limit` propositions (20 par défaut) adaptées à la requête multi-mots.
    public static func suggest(for query: String, limit: Int = 20) -> [String] {
        let clean = normalize(query)
        guard !clean.isEmpty else {
            return Array(default20.prefix(limit))
        }

        var results: [String] = []
        var seen = Set<String>()

        func appendIcon(_ icon: String) {
            guard !seen.contains(icon) else { return }
            seen.insert(icon)
            results.append(icon)
        }

        // 1. Résultats du moteur multi-mots
        let matched = search(query: clean, limit: limit)
        for icon in matched {
            appendIcon(icon)
            if results.count >= limit { break }
        }

        // 2. Compléter jusqu'à 20 avec les 20 icônes par défaut
        if results.count < limit {
            for fallback in default20 {
                appendIcon(fallback)
                if results.count >= limit { break }
            }
        }

        return Array(results.prefix(limit))
    }
}
