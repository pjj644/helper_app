import { ThemeManager } from '../utils/ThemeManager';

export interface InlineSpanItem {
  text: string;
  isBold?: boolean;
  isCode?: boolean;
}

export interface KeyValueItem {
  label: string;
  value: string;
}

export interface MarkdownBlockItem {
  id: string;
  type: 'paragraph' | 'heading' | 'list_item' | 'quote' | 'table' | 'code' | 'card';
  level?: number;
  spans: InlineSpanItem[];
  listPrefix?: string;
  tableHeaders?: string[];
  tableRows?: string[][];
  codeContent?: string;
  cardTitle?: string;
  cardFields?: KeyValueItem[];
}

/**
 * 专业级 ArkTS Markdown 与语义化排版解析器（Claude Code 极简风格）
 */
export class MarkdownParser {
  /**
   * 解析行内加粗 **text** 与行内代码 `code`
   */
  static parseInlineSpans(text: string): InlineSpanItem[] {
    const spans: InlineSpanItem[] = [];
    if (!text || text.length === 0) {
      return spans;
    }

    const regex = /(\*\*([^*]+)\*\*|`([^`]+)`)/g;
    let lastIdx = 0;
    let match: RegExpExecArray | null = null;

    while ((match = regex.exec(text)) !== null) {
      if (match.index > lastIdx) {
        spans.push({ text: text.substring(lastIdx, match.index), isBold: false, isCode: false });
      }

      if (match[2] !== undefined) {
        spans.push({ text: match[2], isBold: true, isCode: false });
      } else if (match[3] !== undefined) {
        spans.push({ text: match[3], isBold: false, isCode: true });
      }
      lastIdx = regex.lastIndex;
    }

    if (lastIdx < text.length) {
      spans.push({ text: text.substring(lastIdx), isBold: false, isCode: false });
    }

    if (spans.length === 0) {
      spans.push({ text: text, isBold: false, isCode: false });
    }
    return spans;
  }

  /**
   * 解析全文为结构化 Block
   */
  static parseToBlocks(rawText: string): MarkdownBlockItem[] {
    const blocks: MarkdownBlockItem[] = [];
    if (!rawText) return blocks;

    // 1. 预处理：规范化标题与换行，清理多余的装饰 emoji
    let formattedText = rawText
      // 标题与卡片前强制双换行
      .replace(/([^\n])\s*(###?\s+)/gu, '$1\n\n$2')
      .replace(/([^\n])\s*[📌📚🗓️📅]\s*/gu, '$1\n\n### ')
      .replace(/^[📌📚🗓️📅]\s*/gu, '### ')
      // 在行内紧挨着的 "- 教师" / "- 教室" / "- 时间" 等属性前强制补充换行
      .replace(
        /([^\n])\s*-\s*([^-\n]*?(?:教师|教室|地点|时间|节次|成绩|绩点|学分|周次|状态|倒计时|类型|标题|科目)[：:])/gu,
        '$1\n- $2',
      )
      // 过滤装饰型 emoji 保持极简高质感
      .replace(/[📌🎒👨‍🏫📍⏰📝📚🗓️📅]/gu, '')
      // 规范化总结语句换行
      .replace(/\)\s*(两节课|三节课|四节课|一节课|共\d+节|下午|上午|以上是|如需|需要我)/gu, ')\n\n$1')
      // 过滤孤立的无标题 ### 标记行（防止模型输出裸 ###）
      .replace(/^\s*#+\s*$/gm, '');

    const lines = formattedText.split('\n');
    let inCodeBlock = false;
    let codeBuffer: string[] = [];
    let tableBuffer: string[] = [];
    let blockIdCounter = 0;

    const flushTable = () => {
      if (tableBuffer.length >= 2) {
        const headerLine = tableBuffer[0];
        const headers = headerLine
          .split('|')
          .map((s) => s.trim())
          .filter((s, idx, arr) => (idx > 0 && idx < arr.length - 1) || (idx === 0 && s.length > 0));

        const rows: string[][] = [];
        for (let i = 1; i < tableBuffer.length; i++) {
          const rowLine = tableBuffer[i].trim();
          if (/^\|?[\s\-:|]+\|?$/.test(rowLine)) {
            continue;
          }
          const cells = rowLine
            .split('|')
            .map((s) => s.trim())
            .filter((s, idx, arr) => (idx > 0 && idx < arr.length - 1) || (idx === 0 && s.length > 0));
          if (cells.length > 0) {
            rows.push(cells);
          }
        }

        blocks.push({
          id: `tbl_${blockIdCounter++}`,
          type: 'table',
          spans: [],
          tableHeaders: headers,
          tableRows: rows,
        });
      } else if (tableBuffer.length === 1) {
        blocks.push({
          id: `p_${blockIdCounter++}`,
          type: 'paragraph',
          spans: MarkdownParser.parseInlineSpans(tableBuffer[0]),
        });
      }
      tableBuffer = [];
    };

    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      const trimmed = line.trim();

      // 1. 代码块检测 ```
      if (trimmed.startsWith('```')) {
        if (inCodeBlock) {
          blocks.push({
            id: `code_${blockIdCounter++}`,
            type: 'code',
            spans: [],
            codeContent: codeBuffer.join('\n'),
          });
          codeBuffer = [];
          inCodeBlock = false;
        } else {
          inCodeBlock = true;
          codeBuffer = [];
        }
        i++;
        continue;
      }

      if (inCodeBlock) {
        codeBuffer.push(line);
        i++;
        continue;
      }

      // 2. 表格行检测
      if (trimmed.startsWith('|') || (trimmed.includes('|') && /\|.*\|/.test(trimmed))) {
        tableBuffer.push(trimmed);
        i++;
        continue;
      } else if (tableBuffer.length > 0) {
        flushTable();
      }

      if (trimmed.length === 0) {
        i++;
        continue;
      }

      // 3. 结构化卡片块识别（如 ### 课程名 紧随 - 教师 / - 教室 / - 时间）
      if (trimmed.startsWith('### ') || (trimmed.startsWith('**') && trimmed.endsWith('**') && trimmed.length < 35)) {
        const title = trimmed.replace(/^###\s+/, '').replace(/\*\*/g, '').trim();
        const cardFields: KeyValueItem[] = [];

        let j = i + 1;
        while (j < lines.length) {
          const nextTrimmed = lines[j].trim();
          if (nextTrimmed.length === 0) {
            j++;
            break;
          }
          if (nextTrimmed.startsWith('###') || nextTrimmed.startsWith('#')) {
            break;
          }

          // 匹配属性项（如 - 教师：陈碟 或 - 教室：品学楼B303）
          if (nextTrimmed.startsWith('- ') || nextTrimmed.startsWith('• ')) {
            const itemText = nextTrimmed.replace(/^[-•]\s*/, '');
            const colonIdx = itemText.indexOf('：') !== -1 ? itemText.indexOf('：') : itemText.indexOf(':');

            if (colonIdx !== -1) {
              const labelPart = itemText.substring(0, colonIdx).trim();
              const valuePart = itemText.substring(colonIdx + 1).trim();
              cardFields.push({
                label: labelPart,
                value: valuePart,
              });
            } else {
              cardFields.push({
                label: '说明',
                value: itemText,
              });
            }
            j++;
          } else {
            break;
          }
        }

        if (cardFields.length > 0) {
          blocks.push({
            id: `card_${blockIdCounter++}`,
            type: 'card',
            cardTitle: title,
            cardFields: cardFields,
            spans: [],
          });
          i = j;
          continue;
        }
      }

      // 4. 普通标题检测 #, ##, ###
      if (trimmed.startsWith('### ')) {
        blocks.push({
          id: `h3_${blockIdCounter++}`,
          type: 'heading',
          level: 3,
          spans: MarkdownParser.parseInlineSpans(trimmed.substring(4)),
        });
      } else if (trimmed.startsWith('## ')) {
        blocks.push({
          id: `h2_${blockIdCounter++}`,
          type: 'heading',
          level: 2,
          spans: MarkdownParser.parseInlineSpans(trimmed.substring(3)),
        });
      } else if (trimmed.startsWith('# ')) {
        blocks.push({
          id: `h1_${blockIdCounter++}`,
          type: 'heading',
          level: 1,
          spans: MarkdownParser.parseInlineSpans(trimmed.substring(2)),
        });
      }
      // 5. 引用块 >
      else if (trimmed.startsWith('> ')) {
        blocks.push({
          id: `q_${blockIdCounter++}`,
          type: 'quote',
          spans: MarkdownParser.parseInlineSpans(trimmed.substring(2)),
        });
      }
      // 6. 列表项 (- , * , 1. )
      else if (/^[-*]\s+/.test(trimmed)) {
        blocks.push({
          id: `li_${blockIdCounter++}`,
          type: 'list_item',
          listPrefix: '– ',
          spans: MarkdownParser.parseInlineSpans(trimmed.replace(/^[-*]\s+/, '')),
        });
      } else if (/^\d+\.\s+/.test(trimmed)) {
        const match = trimmed.match(/^(\d+\.)\s+(.*)/);
        const prefix = match ? match[1] + ' ' : '1. ';
        const content = match ? match[2] : trimmed;
        blocks.push({
          id: `li_${blockIdCounter++}`,
          type: 'list_item',
          listPrefix: prefix,
          spans: MarkdownParser.parseInlineSpans(content),
        });
      }
      // 7. 普通段落
      else {
        blocks.push({
          id: `p_${blockIdCounter++}`,
          type: 'paragraph',
          spans: MarkdownParser.parseInlineSpans(trimmed),
        });
      }

      i++;
    }

    if (tableBuffer.length > 0) {
      flushTable();
    }
    if (inCodeBlock && codeBuffer.length > 0) {
      blocks.push({
        id: `code_${blockIdCounter++}`,
        type: 'code',
        spans: [],
        codeContent: codeBuffer.join('\n'),
      });
    }

    return blocks;
  }
}

/**
 * 原生 ArkTS Markdown 极简高质感渲染组件
 */
@Component
export struct MarkdownBubble {
  @Prop content: string = '';
  @Prop isUser: boolean = false;
  @Prop isError: boolean = false;
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;

  private getBlocks(): MarkdownBlockItem[] {
    return MarkdownParser.parseToBlocks(this.content);
  }

  build() {
    Column({ space: 8 }) {
      ForEach(this.getBlocks(), (block: MarkdownBlockItem) => {
        if (block.type === 'card') {
          // 🏆 极简语义化卡片：左侧细致强调线 + 浅灰卡片背景 + 标签化键值对
          Column({ space: 6 }) {
            // 卡片标题
            Row({ space: 6 }) {
              Column()
                .width(3)
                .height(14)
                .backgroundColor('#007AFF')
                .borderRadius(1.5)

              Text(block.cardTitle || '')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isDarkMode ? '#E2E8F0' : '#1D2A3A')
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 卡片各项属性
            if (block.cardFields) {
              Column({ space: 4 }) {
                ForEach(block.cardFields, (field: KeyValueItem) => {
                  Row({ space: 6 }) {
                    Text(field.label)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(ThemeManager.getTextSecondaryColor())
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(this.isDarkMode ? '#242C3D' : '#EAEFF8')
                      .borderRadius(4)
                      .flexShrink(0)

                    Text(field.value)
                      .fontSize(13)
                      .fontColor(ThemeManager.getTextPrimaryColor())
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                })
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 6, bottom: 6 })
              .backgroundColor(this.isDarkMode ? '#1E2433' : '#F6F8FC')
              .borderRadius(8)
            }
          }
          .width('100%')
          .padding(10)
          .borderRadius(10)
          .backgroundColor(this.isDarkMode ? '#1A202C' : '#FFFFFF')
          .border({
            width: 0.5,
            color: this.isDarkMode ? '#2D3748' : '#E2E8F0',
          })
          .margin({ top: 2, bottom: 2 })
          .clip(true)
        } else if (block.type === 'heading') {
          Row({ space: 6 }) {
            Column()
              .width(3)
              .height(block.level === 1 ? 16 : (block.level === 2 ? 14 : 12))
              .backgroundColor('#007AFF')
              .borderRadius(1.5)

            Text() {
              ForEach(block.spans, (span: InlineSpanItem) => {
                Span(span.text)
                  .fontSize(block.level === 1 ? 17 : (block.level === 2 ? 16 : 15))
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isUser ? '#FFFFFF' : ThemeManager.getTextPrimaryColor())
              })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 4, bottom: 2 })
        } else if (block.type === 'quote') {
          Row() {
            Column()
              .width(2)
              .height('100%')
              .backgroundColor('#8A95A8')
              .borderRadius(1)
              .margin({ right: 8 })

            Text() {
              ForEach(block.spans, (span: InlineSpanItem) => {
                Span(span.text)
                  .fontSize(14)
                  .fontStyle(FontStyle.Italic)
                  .fontColor(ThemeManager.getTextSecondaryColor())
              })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        } else if (block.type === 'list_item') {
          Row({ space: 6 }) {
            Text(block.listPrefix || '– ')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isUser ? '#FFFFFF' : ThemeManager.getTextSecondaryColor())
              .alignSelf(ItemAlign.Start)

            Text() {
              ForEach(block.spans, (span: InlineSpanItem) => {
                Span(span.text)
                  .fontSize(14)
                  .fontWeight(span.isBold ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.isUser ? '#FFFFFF' : (span.isCode ? '#D63200' : ThemeManager.getTextPrimaryColor()))
              })
            }
            .layoutWeight(1)
            .lineHeight(20)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else if (block.type === 'table') {
          // 响应式表格：极简灰白与边框分割（Claude Code 风格）
          Column() {
            if (block.tableHeaders && block.tableHeaders.length > 0) {
              Row() {
                ForEach(block.tableHeaders, (headerText: string) => {
                  Text(headerText)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.isDarkMode ? '#E2E8F0' : '#2D3748')
                    .layoutWeight(1)
                    .textAlign(TextAlign.Center)
                    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
                })
              }
              .width('100%')
              .backgroundColor(this.isDarkMode ? '#2D3748' : '#EDF2F7')
              .borderRadius({ topLeft: 6, topRight: 6 })
            }

            if (block.tableRows) {
              ForEach(block.tableRows, (rowCells: string[], rowIdx: number) => {
                Row() {
                  ForEach(rowCells, (cellText: string) => {
                    Text(cellText)
                      .fontSize(12)
                      .fontColor(ThemeManager.getTextPrimaryColor())
                      .layoutWeight(1)
                      .textAlign(TextAlign.Center)
                      .padding({ top: 6, bottom: 6, left: 4, right: 4 })
                  })
                }
                .width('100%')
                .backgroundColor(
                  rowIdx % 2 === 0
                    ? (this.isDarkMode ? '#1A202C' : '#FFFFFF')
                    : (this.isDarkMode ? '#242D3D' : '#F7FAFC')
                )
                .border({
                  width: { top: 0.5 },
                  color: this.isDarkMode ? '#334155' : '#E2E8F0',
                })
              })
            }
          }
          .width('100%')
          .borderRadius(6)
          .border({ width: 0.5, color: this.isDarkMode ? '#334155' : '#CBD5E1' })
          .margin({ top: 4, bottom: 4 })
          .clip(true)
        } else if (block.type === 'code') {
          // 代码块：暗色高亮
          Column() {
            Text(block.codeContent || '')
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(this.isDarkMode ? '#E0E0E0' : '#24292E')
              .copyOption(CopyOptions.LocalDevice)
          }
          .width('100%')
          .padding(8)
          .borderRadius(6)
          .backgroundColor(this.isDarkMode ? '#1E1E2E' : '#F4F5F7')
          .border({ width: 0.5, color: this.isDarkMode ? '#2E3440' : '#E2E8F0' })
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 4, bottom: 4 })
        } else {
          // 普通段落
          Text() {
            ForEach(block.spans, (span: InlineSpanItem) => {
              Span(span.text)
                .fontSize(15)
                .fontWeight(span.isBold ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(
                  this.isUser
                    ? '#FFFFFF'
                    : (this.isError ? '#FF3B30' : (span.isCode ? '#D63200' : ThemeManager.getTextPrimaryColor()))
                )
            })
          }
          .width('100%')
          .lineHeight(22)
          .copyOption(CopyOptions.LocalDevice)
        }
      }, (block: MarkdownBlockItem) => block.id)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
