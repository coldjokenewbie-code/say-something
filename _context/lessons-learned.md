# lessons-learned(say-something)

## 2026-07-16 指揮官收尾清單必逐項核,不能只改「記得的那幾個」[Claude@Mac]

- **事實**:iOS 任務連兩個契約都在收尾被 verifier 抓 FAIL——第一次 mirror 未 commit+_context 未更新;第二次 TaskLog 狀態列與 INDEX.md 漏帶新階段、Drive 缺 ios/README.md(自 b69458e 起只存 mirror 的漂移)。
- **根因**:收尾動作憑記憶做,改了待辦 checkbox 卻漏狀態列/INDEX;Drive↔mirror 同步只顧「這次改的檔」,沒對照兩邊清單。
- **規則(收尾固定五步,宣稱完成前逐項打勾)**:
  1. TaskLog 待辦 checkbox **且狀態列**同步更新
  2. INDEX.md 現況段納入本次階段
  3. `diff -rq` Drive vs mirror 的受動目錄(缺檔=漂移,不是「這次沒改」)
  4. mirror commit(契約有授權才做)
  5. coach check 之後才派 verifier
- 對應機制:ody-verifier checklist 第 6 條(收尾核驗)已能攔;本條是指揮官端的事前清單,別靠 verifier 當保底。
