unit SimpleXML;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Classes, DOM, XMLRead, XMLWrite, Generics.Collections;

type
  TXmlValueType = (xvtNull, xvtString, xvtNumber, xvtBoolean, xvtElement, xvtNodeList);

  TXmlFlatItem = record
    Path: string;      // 路径，如 "root/child[0]/@attr"
    ValueType: TXmlValueType;
    Value: string;     // 统一转为字符串
  end;

  TXmlFlatItems = array of TXmlFlatItem;

  IXmlNode = interface;
  IXmlNodeList = interface;

  IXmlNodeList = interface ['{E6F7A8B9-C0D1-42E3-94F5-67890ABCDEF1}']
    function GetCount: Integer;
    function GetItem(Index: Integer): IXmlNode;
    procedure Add(Node: IXmlNode);
    procedure Delete(Index: Integer);
    procedure Clear;
    function ToXML: string;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: IXmlNode read GetItem; default;
  end;

  IXmlNode = interface ['{F1234567-89AB-CDEF-0123-456789ABCDEF}']
    // 基本属性
    function GetName: string;
    function GetText: string;
    procedure SetText(const Value: string);
    function GetAttribute(const AttrName: string): string;
    procedure SetAttribute(const AttrName, Value: string);
    // 子节点访问（单个或列表）
    function GetNode(const Name: string): IXmlNode;         // 返回第一个匹配的子节点
    function GetNodes(const Name: string): IXmlNodeList;   // 返回所有匹配的子节点列表
    // 路径访问（支持XPath简化语法）
    function GetPath(const Path: string): string;          // 返回原始字符串值
    // 类型化取值（通过路径）
    function GetS(const Path: string): string;
    function GetI(const Path: string): Integer;
    function GetL(const Path: string): Int64;
    function GetF(const Path: string): Double;
    function GetB(const Path: string): Boolean;
    function GetD(const Path: string): TDateTime;
    // 类型化赋值（通过路径，用于设置元素文本或属性）
    procedure SetS(const Path, Value: string);
    procedure SetI(const Path: string; Value: Integer);
    procedure SetL(const Path: string; Value: Int64);
    procedure SetF(const Path: string; Value: Double);
    procedure SetB(const Path: string; Value: Boolean);
    procedure SetD(const Path: string; Value: TDateTime);
    // 添加子节点
    function AddNode(const Name: string): IXmlNode;        // 添加元素节点，返回新节点
    function AddText(const Text: string): IXmlNode;        // 添加文本节点
    // 删除
    procedure RemoveChild(const Name: string);             // 删除第一个匹配的子元素
    procedure RemoveAllChildren(const Name: string);       // 删除所有匹配的子元素
    procedure Clear;                                       // 清空所有子节点
    // 序列化
    function ToXML: string;                                // 紧凑XML
    function Format: string;                               // 格式化XML
    procedure SaveToFile(const FileName: string);
    // 克隆
    function Clone: IXmlNode;
    // 扁平化
    function Flatten: TXmlFlatItems;

    property Name: string read GetName;
    property Text: string read GetText write SetText;
    property Attribute[const AttrName: string]: string read GetAttribute write SetAttribute;
    property Node[const Name: string]: IXmlNode read GetNode;
    property Nodes[const Name: string]: IXmlNodeList read GetNodes;
    property Path[const Path: string]: string read GetPath;
  end;

// 全局辅助函数
function ParseXML(const XMLString: string): IXmlNode;
function LoadXMLFromFile(const FileName: string): IXmlNode;
function TryParseXMLDateTime(const S: string; out Value: TDateTime): Boolean;

implementation

uses
  DateUtils, Character;

const
  XML_DATE_FORMAT = 'yyyy-mm-dd"T"hh:nn:ss.zzz';

type
  TXmlNodeList = class(TInterfacedObject, IXmlNodeList)
  private
    FList: TList<IXmlNode>;
    FOwned: Boolean; // 是否负责释放内部节点（通常为False，因为节点由DOM管理）
  public
    constructor Create(AOwned: Boolean = False);
    destructor Destroy; override;
    function GetCount: Integer;
    function GetItem(Index: Integer): IXmlNode;
    procedure Add(Node: IXmlNode);
    procedure Delete(Index: Integer);
    procedure Clear;
    function ToXML: string;
  end;

  TXmlNode = class(TInterfacedObject, IXmlNode)
  private
    FElement: TDOMElement;      // 元素节点（如果是文本节点则为nil）
    FTextNode: TDOMText;        // 文本节点（如果是文本节点）
    FDocument: TXMLDocument;    // 所属文档（用于创建新节点）
    FOwned: Boolean;            // 是否负责释放文档
    FNodeType: (ntElement, ntText);
    // 内部辅助方法
    function GetElement: TDOMElement;
    function GetDocument: TXMLDocument;
    function GetTextContent: string;
    procedure SetTextContent(const Value: string);
    function FindNodeByPath(const Path: string; out Node: TDOMNode; out IsAttribute: Boolean; out AttrName: string; out IsText: Boolean): Boolean;
    function GetValueByPath(const Path: string): string;
    procedure SetValueByPath(const Path, Value: string);
  public
    // 构造函数（用于元素）
    constructor Create(ADocument: TXMLDocument; AElement: TDOMElement; AOwned: Boolean = False); overload;
    // 构造函数（用于文本节点，通常不直接调用）
    constructor Create(ADocument: TXMLDocument; AText: TDOMText; AOwned: Boolean = False); overload;
    destructor Destroy; override;
    // 接口实现
    function GetName: string;
    function GetText: string;
    procedure SetText(const Value: string);
    function GetAttribute(const AttrName: string): string;
    procedure SetAttribute(const AttrName, Value: string);
    function GetNode(const Name: string): IXmlNode;
    function GetNodes(const Name: string): IXmlNodeList;
    function GetPath(const Path: string): string;
    function GetS(const Path: string): string;
    function GetI(const Path: string): Integer;
    function GetL(const Path: string): Int64;
    function GetF(const Path: string): Double;
    function GetB(const Path: string): Boolean;
    function GetD(const Path: string): TDateTime;
    procedure SetS(const Path, Value: string);
    procedure SetI(const Path: string; Value: Integer);
    procedure SetL(const Path: string; Value: Int64);
    procedure SetF(const Path: string; Value: Double);
    procedure SetB(const Path: string; Value: Boolean);
    procedure SetD(const Path: string; Value: TDateTime);
    function AddNode(const Name: string): IXmlNode;
    function AddText(const Text: string): IXmlNode;
    procedure RemoveChild(const Name: string);
    procedure RemoveAllChildren(const Name: string);
    procedure Clear;
    function ToXML: string;
    function Format: string;
    procedure SaveToFile(const FileName: string);
    function Clone: IXmlNode;
    function Flatten: TXmlFlatItems;
    // 静态工厂方法（不在接口中声明，使用类直接调用）
    class function Parse(const XMLString: string): IXmlNode; static;
    class function ParseFile(const FileName: string): IXmlNode; static;
    class function LoadFromFile(const FileName: string): IXmlNode; static;
  end;

{ TXmlNodeList }

constructor TXmlNodeList.Create(AOwned: Boolean);
begin
  inherited Create;
  FList := TList<IXmlNode>.Create;
  FOwned := AOwned;
end;

destructor TXmlNodeList.Destroy;
var
  i: Integer;
begin
  if FOwned then
    for i := 0 to FList.Count - 1 do
      FList[i] := nil; // 接口引用计数自动管理，无需显式释放
  FList.Free;
  inherited;
end;

function TXmlNodeList.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TXmlNodeList.GetItem(Index: Integer): IXmlNode;
begin
  if (Index >= 0) and (Index < FList.Count) then
    Result := FList[Index]
  else
    Result := nil;
end;

procedure TXmlNodeList.Add(Node: IXmlNode);
begin
  if Assigned(Node) then
    FList.Add(Node);
end;

procedure TXmlNodeList.Delete(Index: Integer);
begin
  if (Index >= 0) and (Index < FList.Count) then
    FList.Delete(Index);
end;

procedure TXmlNodeList.Clear;
begin
  FList.Clear;
end;

function TXmlNodeList.ToXML: string;
var
  sb: TStringBuilder;
  i: Integer;
begin
  sb := TStringBuilder.Create;
  try
    for i := 0 to FList.Count - 1 do
      sb.Append(FList[i].ToXML);
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

{ TXmlNode }

constructor TXmlNode.Create(ADocument: TXMLDocument; AElement: TDOMElement; AOwned: Boolean);
begin
  inherited Create;
  FDocument := ADocument;
  FElement := AElement;
  FNodeType := ntElement;
  FOwned := AOwned;
  FTextNode := nil;
end;

constructor TXmlNode.Create(ADocument: TXMLDocument; AText: TDOMText; AOwned: Boolean);
begin
  inherited Create;
  FDocument := ADocument;
  FTextNode := AText;
  FNodeType := ntText;
  FOwned := AOwned;
  FElement := nil;
end;

destructor TXmlNode.Destroy;
begin
  if FOwned then
  begin
    if Assigned(FDocument) then
      FDocument.Free;
  end;
  inherited;
end;

function TXmlNode.GetElement: TDOMElement;
begin
  if FNodeType = ntElement then
    Result := FElement
  else
    Result := nil;
end;

function TXmlNode.GetDocument: TXMLDocument;
begin
  Result := FDocument;
end;

function TXmlNode.GetTextContent: string;
begin
  if FNodeType = ntElement then
    Result := FElement.TextContent
  else if FNodeType = ntText then
    Result := FTextNode.TextContent
  else
    Result := '';
end;

procedure TXmlNode.SetTextContent(const Value: string);
begin
  if FNodeType = ntElement then
    FElement.TextContent := Value
  else if FNodeType = ntText then
    FTextNode.TextContent := Value;
end;

// 简化的XPath解析：支持 / 分隔，[index] 索引，@属性，text()
function TXmlNode.FindNodeByPath(const Path: string; out Node: TDOMNode; out IsAttribute: Boolean; out AttrName: string; out IsText: Boolean): Boolean;
var
  Steps: TArray<string>;
  CurrentNode: TDOMNode;
  i, Index: Integer;
  Step, StepName, IndexStr: string;
  ChildNode: TDOMNode;
  Found: Boolean;
  LBr,RBr,ChildIndex:Integer;
begin
  Result := False;
  Node := nil;
  IsAttribute := False;
  IsText := False;
  AttrName := '';

  if Path = '' then Exit;

  // 按 / 分割路径（忽略首尾空白）
  Steps := Path.Split(['/'], TStringSplitOptions.ExcludeEmpty);
  if Length(Steps) = 0 then Exit;

  if FNodeType = ntElement then
    CurrentNode := FElement
  else
    CurrentNode := nil;

  if not Assigned(CurrentNode) then Exit;

  for i := 0 to Length(Steps) - 1 do
  begin
    Step := Steps[i];
    if Step.StartsWith('@') then
    begin
      // 属性
      if i = Length(Steps) - 1 then
      begin
        IsAttribute := True;
        AttrName := Step.Substring(1);
        Node := CurrentNode; // 返回元素节点，属性由外部处理
        Result := True;
        Exit;
      end
      else
        Exit; // 属性必须出现在最后一步
    end
    else if Step = 'text()' then
    begin
      // 文本节点
      if i = Length(Steps) - 1 then
      begin
        IsText := True;
        Node := CurrentNode;
        Result := True;
        Exit;
      end
      else
        Exit;
    end
    else
    begin
      // 元素名，可能有索引
      Index := -1;
      IndexStr := '';
      LBr := Step.IndexOf('[');
      if LBr >= 0 then
      begin
        RBr := Step.IndexOf(']', LBr);
        if RBr > LBr then
        begin
          StepName := Step.Substring(0, LBr);
          IndexStr := Step.Substring(LBr + 1, RBr - LBr - 1);
          if not TryStrToInt(IndexStr, Index) then
            Index := -1;
        end
        else
          StepName := Step;
      end
      else
        StepName := Step;

      // 查找子节点
      Found := False;
      ChildIndex := 0;
      ChildNode := CurrentNode.FirstChild;
      while Assigned(ChildNode) do
      begin
        if (ChildNode.NodeType = ELEMENT_NODE) and (TDOMElement(ChildNode).TagName = StepName) then
        begin
          if (Index < 0) or (ChildIndex = Index) then
          begin
            Found := True;
            Break;
          end;
          Inc(ChildIndex);
        end;
        ChildNode := ChildNode.NextSibling;
      end;

      if not Found then
        Exit;

      CurrentNode := ChildNode;
    end;
  end;

  Node := CurrentNode;
  Result := True;
end;

function TXmlNode.GetValueByPath(const Path: string): string;
var
  Node: TDOMNode;
  IsAttr, IsText: Boolean;
  AttrName: string;
begin
  Result := '';
  if FindNodeByPath(Path, Node, IsAttr, AttrName, IsText) then
  begin
    if IsAttr then
    begin
      if Node.NodeType = ELEMENT_NODE then
        Result := TDOMElement(Node).GetAttribute(AttrName);
    end
    else if IsText then
    begin
      Result := Node.TextContent;
    end
    else
    begin
      if Assigned(Node) then
        Result := Node.TextContent;
    end;
  end;
end;

procedure TXmlNode.SetValueByPath(const Path, Value: string);
var
  Node: TDOMNode;
  IsAttr, IsText: Boolean;
  AttrName: string;
begin
  if FindNodeByPath(Path, Node, IsAttr, AttrName, IsText) then
  begin
    if IsAttr then
    begin
      if Node.NodeType = ELEMENT_NODE then
        TDOMElement(Node).SetAttribute(AttrName, Value);
    end
    else if IsText then
    begin
      Node.TextContent := Value;
    end
    else
    begin
      Node.TextContent := Value;
    end;
  end;
end;

// 接口实现
function TXmlNode.GetName: string;
begin
  if FNodeType = ntElement then
    Result := FElement.TagName
  else
    Result := '#text';
end;

function TXmlNode.GetText: string;
begin
  Result := GetTextContent;
end;

procedure TXmlNode.SetText(const Value: string);
begin
  SetTextContent(Value);
end;

function TXmlNode.GetAttribute(const AttrName: string): string;
begin
  if FNodeType = ntElement then
    Result := FElement.GetAttribute(AttrName)
  else
    Result := '';
end;

procedure TXmlNode.SetAttribute(const AttrName, Value: string);
begin
  if FNodeType = ntElement then
    FElement.SetAttribute(AttrName, Value);
end;

function TXmlNode.GetNode(const Name: string): IXmlNode;
var
  Child: TDOMNode;
begin
  Result := nil;
  if FNodeType <> ntElement then Exit;
  Child := FElement.FirstChild;
  while Assigned(Child) do
  begin
    if (Child.NodeType = ELEMENT_NODE) and (TDOMElement(Child).TagName = Name) then
    begin
      Result := TXmlNode.Create(FDocument, TDOMElement(Child), False);
      Break;
    end;
    Child := Child.NextSibling;
  end;
end;

function TXmlNode.GetNodes(const Name: string): IXmlNodeList;
var
  Child: TDOMNode;
  List: TXmlNodeList;
  SlashPos: Integer;
  FirstPart, RestPart: string;
  ParentNodes: IXmlNodeList;
  ChildList: IXmlNodeList;
  i, j: Integer;
begin
  // 新增：支持路径解析（如 'Users/User'）
  SlashPos := Name.IndexOf('/');
  if SlashPos > 0 then
  begin
    FirstPart := Name.Substring(0, SlashPos);
    RestPart := Name.Substring(SlashPos + 1);

    // 递归获取上一层的节点列表
    ParentNodes := GetNodes(FirstPart);
    List := TXmlNodeList.Create(False);

    // 将每一层匹配到的子节点合并到最终结果中
    for i := 0 to ParentNodes.Count - 1 do
    begin
      ChildList := ParentNodes[i].GetNodes(RestPart);
      for j := 0 to ChildList.Count - 1 do
        List.Add(ChildList[j]);
    end;
    Result := List;
  end
  else
  begin
    // 原有逻辑：仅查找直接子节点
    List := TXmlNodeList.Create(False);
    if FNodeType = ntElement then
    begin
      Child := FElement.FirstChild;
      while Assigned(Child) do
      begin
        if (Child.NodeType = ELEMENT_NODE) and (TDOMElement(Child).TagName = Name) then
          List.Add(TXmlNode.Create(FDocument, TDOMElement(Child), False));
        Child := Child.NextSibling;
      end;
    end;
    Result := List;
  end;
end;

function TXmlNode.GetPath(const Path: string): string;
begin
  Result := GetValueByPath(Path);
end;

function TXmlNode.GetS(const Path: string): string;
begin
  Result := GetValueByPath(Path);
end;

function TXmlNode.GetI(const Path: string): Integer;
var
  S: string;
begin
  S := GetValueByPath(Path);
  if not TryStrToInt(S, Result) then
    Result := 0;
end;

function TXmlNode.GetL(const Path: string): Int64;
var
  S: string;
begin
  S := GetValueByPath(Path);
  if not TryStrToInt64(S, Result) then
    Result := 0;
end;

function TXmlNode.GetF(const Path: string): Double;
var
  S: string;
begin
  S := GetValueByPath(Path);
  if not TryStrToFloat(S, Result) then
    Result := 0.0;
end;

function TXmlNode.GetB(const Path: string): Boolean;
var
  S: string;
begin
  S := GetValueByPath(Path);
  Result := SameText(S, 'true') or (S = '1');
end;

function TXmlNode.GetD(const Path: string): TDateTime;
var
  S: string;
begin
  S := GetValueByPath(Path);
  if not TryParseXMLDateTime(S, Result) then
    Result := 0;
end;

procedure TXmlNode.SetS(const Path, Value: string);
begin
  SetValueByPath(Path, Value);
end;

procedure TXmlNode.SetI(const Path: string; Value: Integer);
begin
  SetValueByPath(Path, IntToStr(Value));
end;

procedure TXmlNode.SetL(const Path: string; Value: Int64);
begin
  SetValueByPath(Path, IntToStr(Value));
end;

procedure TXmlNode.SetF(const Path: string; Value: Double);
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SetValueByPath(Path, FloatToStr(Value, FS));
end;

procedure TXmlNode.SetB(const Path: string; Value: Boolean);
begin
  if Value then
    SetValueByPath(Path, 'true')
  else
    SetValueByPath(Path, 'false');
end;

procedure TXmlNode.SetD(const Path: string; Value: TDateTime);
begin
  SetValueByPath(Path, FormatDateTime(XML_DATE_FORMAT, Value));
end;

function TXmlNode.AddNode(const Name: string): IXmlNode;
var
  NewElem: TDOMElement;
begin
  if FNodeType <> ntElement then
    raise Exception.Create('Cannot add child to a non-element node');
  NewElem := FDocument.CreateElement(Name);
  FElement.AppendChild(NewElem);
  Result := TXmlNode.Create(FDocument, NewElem, False);
end;

function TXmlNode.AddText(const Text: string): IXmlNode;
var
  NewText: TDOMText;
begin
  if FNodeType <> ntElement then
    raise Exception.Create('Cannot add text to a non-element node');
  NewText := FDocument.CreateTextNode(Text);
  FElement.AppendChild(NewText);
  Result := TXmlNode.Create(FDocument, NewText, False);
end;

procedure TXmlNode.RemoveChild(const Name: string);
var
  Child: TDOMNode;
begin
  if FNodeType <> ntElement then Exit;
  Child := FElement.FirstChild;
  while Assigned(Child) do
  begin
    if (Child.NodeType = ELEMENT_NODE) and (TDOMElement(Child).TagName = Name) then
    begin
      FElement.RemoveChild(Child);
      Child.Free;
      Break;
    end;
    Child := Child.NextSibling;
  end;
end;

procedure TXmlNode.RemoveAllChildren(const Name: string);
var
  Child, Next: TDOMNode;
begin
  if FNodeType <> ntElement then Exit;
  Child := FElement.FirstChild;
  while Assigned(Child) do
  begin
    Next := Child.NextSibling;
    if (Child.NodeType = ELEMENT_NODE) and (TDOMElement(Child).TagName = Name) then
    begin
      FElement.RemoveChild(Child);
      Child.Free;
    end;
    Child := Next;
  end;
end;

procedure TXmlNode.Clear;
begin
  if FNodeType = ntElement then
  begin
    while FElement.FirstChild <> nil do
      FElement.RemoveChild(FElement.FirstChild).Free;
  end
  else if FNodeType = ntText then
    FTextNode.TextContent := '';
end;

function TXmlNode.ToXML: string;
var
  Stream: TStringStream;
  s: string;
  i: Integer;
  InTag: Boolean;
  sb: TStringBuilder;
begin
  Stream := TStringStream.Create('');
  try
    // 先按默认格式生成
    WriteXML(FElement, Stream);
    s := Stream.DataString;

    // 手动剔除节点间的换行和缩进，实现真正的紧凑格式
    sb := TStringBuilder.Create;
    try
      InTag := False;
      for i := 1 to Length(s) do
      begin
        if s[i] = '<' then
        begin
          // 遇到新标签开始前，把缓冲区末尾残留的换行和空格全删掉
          while (sb.Length > 0) and CharInSet(sb[sb.Length], [#13, #10, ' ', #9]) do
            sb.Remove(sb.Length - 1, 1);
          sb.Append(s[i]);
          InTag := True;
        end
        else if s[i] = '>' then
        begin
          sb.Append(s[i]);
          InTag := False;
        end
        else if InTag or not CharInSet(s[i], [#13, #10, ' ', #9]) then
        begin
          // 在标签内部（如属性），或者不在标签内且不是空白字符，直接追加
          sb.Append(s[i]);
        end;
        // else: 忽略标签外部的换行和空格（即原本的缩进）
      end;
      Result := sb.ToString;
    finally
      sb.Free;
    end;
  finally
    Stream.Free;
  end;
end;

function TXmlNode.Format: string;
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create('');
  try
    WriteXML(FElement, Stream); // WriteXML 默认带格式，也可以设置格式化选项
    Result := Stream.DataString;
  finally
    Stream.Free;
  end;
end;

procedure TXmlNode.SaveToFile(const FileName: string);
var
  Stream: TFileStream;
begin
  if FNodeType <> ntElement then Exit; // 安全检查：文本节点没有独立的文档可保存

  Stream := TFileStream.Create(FileName, fmCreate);
  try
    WriteXMLFile(FDocument, Stream); // 将 FElement 改为 FDocument
  finally
    Stream.Free;
  end;
end;

function TXmlNode.Clone: IXmlNode;
var
  NewDoc: TXMLDocument;
  NewElem: TDOMElement;
begin
  NewDoc := TXMLDocument.Create;
  NewElem := NewDoc.ImportNode(FElement, True) as TDOMElement;
  NewDoc.AppendChild(NewElem);
  Result := TXmlNode.Create(NewDoc, NewElem, True);
end;

function TXmlNode.Flatten: TXmlFlatItems;
var
  List: TList<TXmlFlatItem>;

  procedure Collect(Node: TDOMNode; const CurrentPath: string);
  var
    i, Index: Integer;
    ChildPath: string;
    Item: TXmlFlatItem;
    Child: TDOMNode;
    Attr: TDOMNode;
    TagName: string;
    Sibling: TDOMNode;
  begin
    if not Assigned(Node) then Exit;

    if Node.NodeType = ELEMENT_NODE then
    begin
      // 收集属性
      for i := 0 to TDOMElement(Node).Attributes.Length - 1 do
      begin
        Attr := TDOMElement(Node).Attributes.Item[i];
        Item.Path := CurrentPath + '/@' + Attr.NodeName;
        Item.ValueType := xvtString;
        Item.Value := Attr.TextContent;
        List.Add(Item);
      end;
      // 收集子元素
      Child := Node.FirstChild;
      while Assigned(Child) do
      begin
        if Child.NodeType = ELEMENT_NODE then
        begin
          // 为每个子元素生成带索引的路径
          TagName := Child.NodeName;
          Index := 0;
          Sibling := Node.FirstChild;
          while Assigned(Sibling) do
          begin
            if (Sibling.NodeType = ELEMENT_NODE) and (Sibling.NodeName = TagName) then
            begin
              if Sibling = Child then Break;
              Inc(Index);
            end;
            Sibling := Sibling.NextSibling;
          end;
          ChildPath := CurrentPath + '/' + TagName + '[' + IntToStr(Index) + ']';
          Collect(Child, ChildPath);
        end
        else if Child.NodeType = TEXT_NODE then
        begin
          // 文本节点：如果非空白且没有其他子节点，则视为内容
          if Trim(Child.TextContent) <> '' then
          begin
            Item.Path := CurrentPath + '/text()';
            Item.ValueType := xvtString;
            Item.Value := Child.TextContent;
            List.Add(Item);
          end;
        end;
        Child := Child.NextSibling;
      end;
    end
    else
    begin
      // 其他节点类型暂不处理
    end;
  end;

var
  i: Integer;
begin
  List := TList<TXmlFlatItem>.Create;
  try
    if Assigned(FElement) then
      Collect(FElement, '');
    SetLength(Result, List.Count);
    for i := 0 to List.Count - 1 do
      Result[i] := List[i];
  finally
    List.Free;
  end;
end;

class function TXmlNode.Parse(const XMLString: string): IXmlNode;
var
  Doc: TXMLDocument;
  Stream: TStringStream;
begin
  Stream := TStringStream.Create(XMLString);
  try
    try
      // Doc 不需要 Create，由 ReadXMLFile 内部创建并输出
      ReadXMLFile(Doc, Stream);
      Result := TXmlNode.Create(Doc, Doc.DocumentElement, True);
    except
      Doc.Free;
      raise;
    end;
  finally
    Stream.Free;
  end;
end;

class function TXmlNode.ParseFile(const FileName: string): IXmlNode;
var
  Doc: TXMLDocument;
  Stream: TFileStream;
begin
  // 使用文件流代替直接传文件名
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    try
      // Doc 不需要 Create，由 ReadXMLFile 内部创建并输出
      ReadXMLFile(Doc, Stream);
      Result := TXmlNode.Create(Doc, Doc.DocumentElement, True);
    except
      Doc.Free;
      raise;
    end;
  finally
    Stream.Free;
  end;
end;

class function TXmlNode.LoadFromFile(const FileName: string): IXmlNode;
begin
  Result := ParseFile(FileName);
end;

{ 全局辅助函数 }

function TryParseXMLDateTime(const S: string; out Value: TDateTime): Boolean;
var
  Year, Month, Day, Hour, Min, Sec, MSec: Word;
  DateStr, TimeStr: string;
  P, TempInt: Integer;
begin
  Result := False;
  Value := 0;
  if S = '' then Exit;

  DateStr := S;
  TimeStr := '';
  P := Pos('T', DateStr);
  if P > 0 then
  begin
    TimeStr := Copy(DateStr, P + 1, MaxInt);
    DateStr := Copy(DateStr, 1, P - 1);
  end;

  if (Length(DateStr) > 10) and CharInSet(DateStr[Length(DateStr) - 5], ['+', '-']) then
  begin
    DateStr := Copy(DateStr, 1, Length(DateStr) - 6);
    TimeStr := '';
  end;

  if (Length(TimeStr) > 1) and (TimeStr[Length(TimeStr)] = 'Z') then
    TimeStr := Copy(TimeStr, 1, Length(TimeStr) - 1);

  if Length(DateStr) >= 10 then
  begin
    if not TryStrToInt(Copy(DateStr, 1, 4), TempInt) then Exit;
    Year := TempInt;
    if not TryStrToInt(Copy(DateStr, 6, 2), TempInt) then Exit;
    Month := TempInt;
    if not TryStrToInt(Copy(DateStr, 9, 2), TempInt) then Exit;
    Day := TempInt;
    if (Year < 1) or (Year > 9999) then Exit;
    if (Month < 1) or (Month > 12) then Exit;
    if (Day < 1) or (Day > 31) then Exit;
  end
  else
    Exit;

  Hour := 0; Min := 0; Sec := 0; MSec := 0;
  if TimeStr <> '' then
  begin
    if Length(TimeStr) >= 2 then
      if TryStrToInt(Copy(TimeStr, 1, 2), TempInt) then Hour := TempInt;
    if Length(TimeStr) >= 5 then
      if TryStrToInt(Copy(TimeStr, 4, 2), TempInt) then Min := TempInt;
    if Length(TimeStr) >= 8 then
      if TryStrToInt(Copy(TimeStr, 7, 2), TempInt) then Sec := TempInt;
    if Length(TimeStr) >= 12 then
      if TryStrToInt(Copy(TimeStr, 10, 3), TempInt) then MSec := TempInt;
  end;

  try
    Value := EncodeDateTime(Year, Month, Day, Hour, Min, Sec, MSec);
    Result := True;
  except
    Result := False;
    Value := 0;
  end;
end;

function ParseXML(const XMLString: string): IXmlNode;
begin
  Result := TXmlNode.Parse(XMLString);
end;

function LoadXMLFromFile(const FileName: string): IXmlNode;
begin
  Result := TXmlNode.LoadFromFile(FileName);
end;

end.
