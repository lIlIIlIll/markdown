package markdown.core

/** 可选的统计计时开关；默认不读取时钟。 */
public class StatisticsOptions {
    /** 是否采集计时信息。 */
    public let timing: Bool
    /**
     * 创建统计选项。
     * @param timing 是否读取时钟采集耗时。
     */
    public init(timing!: Bool = false) {
        this.timing = timing
    }
}
