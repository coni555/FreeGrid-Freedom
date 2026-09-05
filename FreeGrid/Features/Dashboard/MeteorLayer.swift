// 首页深色模式中的装饰流星，不参与财务计算。

import SwiftUI

private struct MeteorParam {
    let width: CGFloat
    let topRatio: CGFloat     // 起始 y / screenHeight
    let delay: TimeInterval   // 起跑延迟(秒)
    let duration: TimeInterval // 一个周期(秒)
}

private let meteorParams: [MeteorParam] = [
    .init(width: 90,  topRatio: 0.10, delay: 1.0, duration: 6.0),
    .init(width: 60,  topRatio: 0.30, delay: 3.5, duration: 8.0),
    .init(width: 110, topRatio: 0.20, delay: 6.0, duration: 5.0),
    .init(width: 45,  topRatio: 0.40, delay: 0.5, duration: 7.0),
]

struct MeteorLayer: View {
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    ForEach(0..<meteorParams.count, id: \.self) { i in
                        Meteor(param: meteorParams[i], time: t, screen: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Meteor: View {
    let param: MeteorParam
    let time: TimeInterval
    let screen: CGSize

    var body: some View {
        // phase 0->1 是一个周期
        let raw = (time - param.delay).truncatingRemainder(dividingBy: param.duration) / param.duration
        let p = CGFloat(raw < 0 ? raw + 1 : raw)

        let startX: CGFloat = -param.width
        let endX: CGFloat = screen.width + 50
        let x = startX + (endX - startX) * p
        let y = param.topRatio * screen.height + 30 * p   // 微微下沉, 模拟 web translateY(30px)

        // opacity 曲线匹配 web @keyframes shoot: 0->0.03 亮起到 0.9, 0.03->0.25 衰减到 0, 之后维持 0
        let opacity: Double = {
            if p < 0.03 { return 0.9 * Double(p / 0.03) }
            if p < 0.25 { return 0.9 * (1 - Double((p - 0.03) / 0.22)) }
            return 0
        }()

        return Rectangle()
            .fill(LinearGradient(
                colors: [
                    Color(red: 184.0/255, green: 216.0/255, blue: 255.0/255).opacity(0.8),
                    Color(red: 156.0/255, green: 195.0/255, blue: 255.0/255).opacity(0.3),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .frame(width: param.width, height: 1)
            .opacity(opacity)
            .offset(x: x, y: y)
    }
}
