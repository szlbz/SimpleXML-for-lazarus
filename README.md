# 1. 从零构建 XML (动态创建)
由于 TXmlNode 被隐藏在 implementation 区，外部不能直接 Create。我们可以通过解析一个空根节点来作为起点，然后动态添加子节点和文本。

```pascal
procedure TForm1.Button5Click(Sender: TObject);
var
  xml, userNode: IXmlNode;
begin
  // 1. 初始化一个空的根节点
  xml := ParseXML('<Users/>');

  // 2. 添加子元素并设置文本
  userNode := xml.AddNode('User');
  userNode.AddText('张三');

  // 3. 给刚才的 User 节点添加属性
  userNode.SetAttribute('Age', '25');
  userNode.SetAttribute('City', '北京');

  // 4. 再添加一个用户 (使用链式调用风格)
  xml.AddNode('User').SetAttribute('Age', '30');

  xml.SaveToFile('Created.xml');
end;
```

# 2. 属性的读取与修改 (Attribute)
除了通过路径 @attr 访问属性，还可以直接通过属性索引器操作。
```pascal
procedure TForm1.Button6Click(Sender: TObject);
var
  xml: IXmlNode;
begin
  xml := ParseXML('<config version="1.0" debug="true"/>');

  // 读取属性
  ShowMessage(xml.Attribute['version']); // 返回 "1.0"

  // 修改属性
  xml.Attribute['version'] := '2.0';
  xml.Attribute['author'] := 'ZhangSan'; // 新增属性

  ShowMessage(xml.ToXML);
  // 输出: <config version="2.0" debug="true" author="ZhangSan"/>
end;
```

# 3. 子节点的直接访问 (Node 与 Nodes)
不使用路径字符串，而是通过面向对象的方式访问层级。
```pascal
procedure TForm1.Button7Click(Sender: TObject);
var
  xml: IXmlNode;
begin
  xml := ParseXML('<root><name>李四</name><age>28</age></root>');

  // 获取单个子节点 (返回第一个匹配的)
  ShowMessage(xml.Node['name'].Text); // 返回 "李四"

  // 修改单个子节点的文本
  xml.Node['age'].Text := '29';

  // 删除特定子节点
  xml.RemoveChild('age');
end;
```

# 4. 遍历同名节点列表 (IXmlNodeList)
当 XML 中有多个同名标签时，可以通过 Nodes 获取列表进行遍历。
```pascal
procedure TForm1.Button8Click(Sender: TObject);
var
  xml: IXmlNode;
  list: IXmlNodeList;
  i: Integer;
begin
  xml := ParseXML('<Students><Stu>甲</Stu><Stu>乙</Stu><Stu>丙</Stu></Students>');

  list := xml.Nodes['Stu'];
  for i := 0 to list.Count - 1 do
  begin
    ShowMessage(list[i].Text); // 依次弹出：甲、乙、丙
  end;

  // 批量删除
  // xml.RemoveAllChildren('Stu');
end;
```

# 5. 带索引的路径访问 (类 XPath)
当有多个同名节点时，可以通过 [index] 精确定位（注意：索引从 0 开始）。
```pascal
procedure TForm1.Button9Click(Sender: TObject);
var
  xml: IXmlNode;
  value: string;
begin
  xml := ParseXML('<root><item id="1">A</item><item id="2">B</item></root>');

  // 直接从 item 开始写（因为 xml 已经是 root 了）
  value := xml.GetS('item[1]/text()'); // 返回 "B"
  ShowMessage(value);

  // 获取第一个 item 的 id 属性
  value := xml.GetS('item[0]/@id'); // 返回 "1"
  ShowMessage(value);
end;
```

# 6. 强类型赋值与取值 (自动类型转换)
框架内置了 Integer、Int64、Double、Boolean、TDateTime 的自动转换，省去了手动 StrToInt 等操作。
```pascal
procedure TForm1.Button10Click(Sender: TObject);
var
  xml: IXmlNode;
begin
  xml := ParseXML('<Data/>');

  // 写入各种类型
  xml.SetI('Data/Count', 100);        // 存为 "100"
  xml.SetF('Data/Price', 19.99);      // 存为 "19.99" (自动处理小数点)
  xml.SetB('Data/IsValid', True);     // 存为 "true"
  xml.SetD('Data/CreateTime', Now);   // 存为 ISO 8601 格式 "2023-10-27T14:30:00.000"

  // 读取各种类型 (如果转换失败会返回默认值 0/False/0.0)
  ShowMessage(IntToStr(xml.GetI('Data/Count')));
  ShowMessage(BoolToStr(xml.GetB('Data/IsValid'), True));
end;
```

# 7. 节点深拷贝
完全克隆一个节点及其所有子节点，生成一个独立的副本，互不影响。
```pascal
procedure TForm1.Button11Click(Sender: TObject);
var
  xml, clonedXml: IXmlNode;
begin
  xml := ParseXML('<root><a>1</a></root>');

  clonedXml := xml.Clone;

  // 修改克隆体，不影响原对象
  clonedXml.Node['a'].Text := '2';

  ShowMessage(xml.Text);        // 输出 1
  ShowMessage(clonedXml.Text);  // 输出 2
end;
```

# 8. 将 XML 扁平化为键值对
这是一个非常实用的功能，它将复杂的树形结构拍平成一维的 Path-Value 数组，非常适合用于日志记录、数据库存储或前端表格展示。
```pascal
procedure TForm1.Button12Click(Sender: TObject);
var
  xml: IXmlNode;
  flatItems: TXmlFlatItems;
  item: TXmlFlatItem;
begin
  xml := ParseXML('<root><user id="1"><name>张三</name></user></root>');

  flatItems := xml.Flatten;

  for item in flatItems do
  begin
    // item.Path  : 路径，如 "root/user[0]/@id", "root/user[0]/name/text()"
    // item.Value : 值，如 "1", "张三"
    Memo1.Lines.Add(Format('%s = %s', [item.Path, item.Value]));
  end;
  // 输出结果：
  // root/user[0]/@id = 1
  // root/user[0]/name/text() = 张三
end;
```

# 9. 序列化输出控制
提供了两种输出方式：紧凑（无换行无空格）和格式化（带缩进，便于人工阅读）。
```pascal
procedure TForm1.Button13Click(Sender: TObject);
var
  xml: IXmlNode;
begin
  xml := ParseXML('<root><a><b>Text</b></a></root>');

  // 紧凑输出（适合网络传输，体积小）
  ShowMessage(xml.ToXML);
  // <root><a><b>Text</b></a></root>

  // 格式化输出（适合保存为配置文件，便于阅读）
  ShowMessage(xml.Format);
  // {
  //   <root>
  //     <a>
  //       <b>Text</b>
  //     </a>
  //   </root>
  // }
end;
```

# 10.使用 LoadXMLFromFile 读取该文件、解析内容、修改并另存为新文件的完整 Demo
```pascal
procedure TForm1.Button14Click(Sender: TObject);
var
  xml: IXmlNode;
  userList: IXmlNodeList;
  w, h: Integer;
begin
  try
    // 1. 从文件加载 XML
    // 注意：如果文件不存在或格式错误，这里会抛出异常
    xml := LoadXMLFromFile('config.xml');

    // 2. 读取普通节点的文本
    ShowMessage('当前应用名称: ' + xml.GetS('App'));

    // 3. 读取节点的属性 (路径直接写 Window/@Width)
    w := xml.GetI('Window/@Width');
    h := xml.GetI('Window/@Height');
    ShowMessage(Format('窗口大小: %d x %d', [w, h]));

    // 4. 获取列表并遍历
    userList := xml.Nodes['Users/User']; // 获取 Users 下的所有 User 节点
    ShowMessage(Format('共有 %d 个用户', [userList.Count]));
    if userList.Count > 0 then
      ShowMessage('第一个用户是: ' + userList[0].Text);

    // 5. 动态修改数据
    xml.SetS('App', 'MyApp Pro');      // 修改应用名称
    xml.SetI('Window/@Width', 1024);   // 修改窗口宽度

    // 6. 将修改后的内容另存为新文件
    xml.SaveToFile('config_new.xml');
    ShowMessage('修改完成并已保存为 config_new.xml');

  except
    on E: Exception do
    begin
      // 捕获并提示错误（例如文件找不到、XML语法错误等）
      ShowMessage('加载XML失败: ' + E.Message);
    end;
  end;
end;
```
