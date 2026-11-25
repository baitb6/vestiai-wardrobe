/// 视觉模型拆分提示词（与模型契约的一部分，改动需同步 [AiMapping]）
const String kSplitOutfitPrompt = '''
你是衣橱单品识别助手。分析全身穿搭图，拆分可独立入库单品。
只返回JSON，不要解释：
{
  "items": [
    {
      "category": "上衣/外套/下装/鞋/配饰/包",
      "subCategory": "T恤/衬衫/牛仔裤/运动鞋等",
      "bbox": {"x":0.1,"y":0.2,"w":0.3,"h":0.4},
      "colors": ["黑色"],
      "styleTags": ["休闲","通勤"],
      "season": ["春","秋"],
      "confidence": 0.86
    }
  ]
}
要求：
1. bbox为0-1归一化坐标；
2. 被遮挡单品也识别但降低confidence；
3. 不输出不存在单品；
4. 配饰最多5件。
''';

/// 网关连通性测试用的最小提示词
const String kGatewayProbePrompt = '回复两个字：可用';
