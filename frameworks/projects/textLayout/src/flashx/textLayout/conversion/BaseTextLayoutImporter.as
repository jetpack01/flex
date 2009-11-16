////////////////////////////////////////////////////////////////////////////////
//
//  ADOBE SYSTEMS INCORPORATED
//  Copyright 2008-2009 Adobe Systems Incorporated
//  All Rights Reserved.
//
//  NOTICE: Adobe permits you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
//////////////////////////////////////////////////////////////////////////////////
package flashx.textLayout.conversion 
{
	import flashx.textLayout.debug.assert;
	import flashx.textLayout.elements.BreakElement;
	import flashx.textLayout.elements.ContainerFormattedElement;
	import flashx.textLayout.elements.FlowElement;
	import flashx.textLayout.elements.FlowGroupElement;
	import flashx.textLayout.elements.FlowLeafElement;
	import flashx.textLayout.elements.GlobalSettings;
	import flashx.textLayout.elements.IConfiguration;
	import flashx.textLayout.elements.ParagraphElement;
	import flashx.textLayout.elements.ParagraphFormattedElement;
	import flashx.textLayout.elements.SpanElement;
	import flashx.textLayout.elements.TabElement;
	import flashx.textLayout.elements.TextFlow;
	import flashx.textLayout.property.Property;
	import flashx.textLayout.tlf_internal;
	use namespace tlf_internal;

	[ExcludeClass]
	/**
	 * @private  
	 * BaseTextLayoutImportFilter is a base class for handling the import/export of TextLayout text in the native format.
	 */ 
	internal class BaseTextLayoutImporter implements ITextImporter
	{	
		private var _ns:Namespace;		// namespace of expected in imported/exported content
		
		private var _errors:Vector.<String>;
		private var _textFlowNamespace:Namespace; // namespace of the TextFlow element against which the namespaces of the following elements are validated
		
		private var _throwOnError:Boolean;
		
		protected var _config:ImportExportConfiguration;
		protected var _textFlowConfiguration:IConfiguration;
		
		// static private const anyPrintChar:RegExp = /[^\s]/g;
		// Consider only tab, line feed, carriage return, and space as characters used for pretty-printing. 
		// While debatable, this is consistent with what CSS does. 
		static private const anyPrintChar:RegExp = /[^\u0009\u000a\u000d\u0020]/g; 

		public function BaseTextLayoutImporter(textFlowConfiguration:IConfiguration, nsValue:Namespace, config:ImportExportConfiguration)
		{
			_textFlowConfiguration = textFlowConfiguration;
			_ns = nsValue;
			_config = config;
		}
		
		protected function clear():void
		{
			if (errors)
				errors.splice(0, errors.length);
			_textFlowNamespace = null;
			_impliedPara = null;
		}
		
		/** Import text content, from an external source, and convert it into a TextFlow.
		 * @param source		source data to convert, may be string or XML
		 * @return TextFlow that was created from the source.
		 */
		public function importToFlow(source:Object):TextFlow
		{
			clear();		// empty results of previous imports
			
			if (_throwOnError)
				return importToFlowCanThrow(source);
			
			var rslt:TextFlow = null;
			var savedErrorHandler:Function = Property.errorHandler;
			try
			{
				Property.errorHandler = importPropertyErrorHandler;
				rslt = importToFlowCanThrow(source);
			}
			catch (e:Error)
			{
				reportError(e.toString());
			}
			Property.errorHandler = savedErrorHandler;
			return rslt;
		}
		
		/** @private */
		protected function importPropertyErrorHandler(p:Property,value:Object):void
		{
			reportError(Property.createErrorString(p,value));
		}
		
		private function importToFlowCanThrow(source:Object):TextFlow
		{
			if (source is String)
				return importFromString(String(source));
			else if (source is XML)
				return importFromXML(XML(source));
			return null;
		}
		
		/** Parse and convert input data.
		 * 
		 * @param source - a string which is in XFL format. String is applied to an XML object then passed
		 * to importFromXML to be processed.  The source must be capable of being cast as an XML
		 * object (E4X). 
		 */
		protected function importFromString(source:String):TextFlow
		{
			var originalSettings:Object = XML.settings();
			try
			{
				XML.ignoreProcessingInstructions = false;		
				XML.ignoreWhitespace = false;
				var xmlTree:XML = new XML(source);				
			}			
			finally
			{
				XML.setSettings(originalSettings);
			}	
			
			return importFromXML(xmlTree);
		}
		
		/** Parse and convert input data.
		 * 
		 * xflSource is a XFL formated object which must be capable of being cast as an XML
		 * object (E4X). 
		 */
		protected function importFromXML(xmlSource:XML):TextFlow
			// Parse an XFL hierarchy into a TextFlow, using the geometry supplied by a TextFrame
			// to host child containers (e.g. tables). This is the main entry point into this class.
		{
			return parseContent(xmlSource[0]);
		}
		
		// This routine imports a TextFlow
		protected function parseContent(rootStory:XML):TextFlow
		{
			// If the root element isn't a textFlow we know how to parse, keep descending the hierarchy.
			var child:XML = rootStory..*::TextFlow[0];
			if (child)
				return parseTextFlow(this, rootStory);
			return null;
		}
		
		/** Returns the namespace used in for writing XML/XFL
		 * 
		 * @return the Namespace being used.
		 */
		public function get ns(): Namespace
		{
			return _ns;
		}
		
		// Remove double spaces, tabs, and newlines.
		// If I have a sequence of different sorts of spaces (e.g., en quad, hair space), would I want them converted down to one space? Probably not.
		// For now, u0020 is the only space character we consider for eliminating duplicates, though u00A0 (non-breaking space) is potentially eligible. 
		static private const dblSpacePattern:RegExp = /[\u0020]{2,}/g;
		// Tab, line feed, and carriage return
		static private const tabNewLinePattern:RegExp = /[\u0009\u000a\u000d]/g;
		protected static function stripWhitespace(insertString:String):String
		{
			// Replace the newlines and tabs inside the element with spaces.
			return insertString.replace(tabNewLinePattern, " ");
		}

		/** Parse XML and convert to  TextFlow. 
		 * @param importFilter	parser object
		 * @param xmlToParse	content to parse
		 * @param parent always null - this parameter is only provided to match FlowElementInfo.importer signature
		 * @return TextFlow	the new TextFlow created as a result of the parse
		 */
		static public function parseTextFlow(importFilter:BaseTextLayoutImporter, xmlToParse:XML, parent:Object=null):TextFlow
		{
			return importFilter.createTextFlowFromXML(xmlToParse, null);
		}		
		
		/** Static method to parse the supplied XML into a paragrph. Parse the <p ...> tag and it's children.
		 * 
		 * @param importFilter	parser object
		 * @param xmlToParse	content to parse
		 * @param parent 		the parent for the new content
		 */
		static public function parsePara(importFilter:BaseTextLayoutImporter, xmlToParse:XML, parent:FlowGroupElement):void
		{
			var paraElem:ParagraphElement = importFilter.createParagraphFromXML(xmlToParse);
			if (importFilter.addChild(parent, paraElem))
			{
				importFilter.parseFlowGroupElementChildren(xmlToParse, paraElem);
				//if parsing an empty paragraph, create a Span for it.
				if (paraElem.numChildren == 0)
					paraElem.addChild(new SpanElement());
			}
		}
		
		static protected function copyAllStyleProps(dst:FlowLeafElement,src:FlowLeafElement):void
		{
			dst.format = src.format;
			dst.styleName       = src.styleName;
			dst.userStyles      = src.userStyles;
			dst.id              = src.id;
		}
		
		/** Static method for constructing a span from XML. Parse the <span> ... </span> tag. 
		 * Insert the span into its parent
		 * 
		 * @param importFilter	parser object
		 * @param xmlToParse	content to parse
		 * @param parent 		the parent for the new content
		 */
		static public function parseSpan(importFilter:BaseTextLayoutImporter, xmlToParse:XML, parent:FlowGroupElement):void
		{
			var firstSpan:SpanElement = importFilter.createSpanFromXML(xmlToParse);
			
			var elemList:XMLList = xmlToParse[0].children();
			if(elemList.length() == 0)
			{
				// Empty span, but may have formatting, so don't strip it out. 
				// Note: the normalizer may yet strip it out if it is not the last child, but that's the normalizer's business.
				importFilter.addChild(parent, firstSpan); 
				return;
			}
	
			for each (var child:XML in elemList) 
			{
				var elemName:String = child.name() ? child.name().localName : null;
					
				if (elemName == null) // span text
				{
					if (firstSpan.parent == null)	// hasn't been used yet
					{
						firstSpan.text = child.toString();
						importFilter.addChild(parent, firstSpan);
					}
					else
					{
						var s:SpanElement = new SpanElement();
						copyAllStyleProps(s,firstSpan);
						s.text = child.toString();
						importFilter.addChild(parent, s);
					}
				}
				else if (elemName == "br")
				{
					var brElem:BreakElement = importFilter.createBreakFromXML(child);	// may be null
					if (brElem)
					{
						copyAllStyleProps(brElem,firstSpan);
						importFilter.addChild(parent, brElem);
					}
					else
						importFilter.reportError(GlobalSettings.getResourceStringFunction("unexpectedXMLElementInSpan",[ elemName ]));
				}
				else if (elemName == "tab")
				{
					var tabElem:TabElement = importFilter.createTabFromXML(child);	// may be null
					if (tabElem)
					{
						copyAllStyleProps(tabElem,firstSpan);
						importFilter.addChild(parent, tabElem);
					}
					else
						importFilter.reportError(GlobalSettings.getResourceStringFunction("unexpectedXMLElementInSpan",[ elemName ]));
				}
				else
					importFilter.reportError(GlobalSettings.getResourceStringFunction("unexpectedXMLElementInSpan",[ elemName ]));				
			}
		}
		
		/** Static method for constructing a break element from XML. Validate the <br> ... </br> tag. 
		 * Use "\u2028" as the text; Insert the new element into its parent 
		 * 
		 * @param importFilter	parser object
		 * @param xmlToParse	content to parse
		 * @param parent 		the parent for the new content
		 */
		static public function parseBreak(importFilter:BaseTextLayoutImporter, xmlToParse:XML, parent:FlowGroupElement):void
		{
			var breakElem:BreakElement = importFilter.createBreakFromXML(xmlToParse);
			importFilter.addChild(parent, breakElem);
		}

		
		/** Static method for constructing a tab element from XML. Validate the <tab> ... </tab> tag. 
		 * Use "\t" as the text; Insert the new element into its parent 
		 * 
		 * @param importFilter	parser object
		 * @param xmlToParse	content to parse
		 * @param parent 		the parent for the new content
		 */
		static public function parseTab(importFilter:BaseTextLayoutImporter, xmlToParse:XML, parent:FlowGroupElement):void
		{
			var tabElem:TabElement = importFilter.createTabFromXML(xmlToParse);	// may be null
			if (tabElem)
				importFilter.addChild(parent, tabElem);
		}
		
		protected function checkNamespace(xmlToParse:XML):Boolean
		{
			var elementNS:Namespace = xmlToParse.namespace();
			if (!_textFlowNamespace) // Not set yet; must be parsing the TextFlow element
			{
				// TextFlow element: allow only empty namespace and flow namespace
				if (elementNS != ns) 
				{
					reportError(GlobalSettings.getResourceStringFunction("unexpectedNamespace", [elementNS.toString()]));
					return false;
				}
				_textFlowNamespace = elementNS;
			}
			// Other elements: must match the namespace of the TextFlow element
			// Specifically, can't be empty unless the TextFlow element's namespace is also empty 
			else if (elementNS != _textFlowNamespace) 
			{
				reportError(GlobalSettings.getResourceStringFunction("unexpectedNamespace", [elementNS.toString()]));
				return false;
			}
			
			return true;
		}
		
		public function parseAttributes(xmlToParse:XML,formatImporters:Array):void
		{
			var importer:IFormatImporter;
			// reset them all
			for each (importer in formatImporters)
				importer.reset();
			
			for each (var item:XML in xmlToParse.attributes())
			{
				var propertyName:String = item.name().localName;
				var propertyValue:String = item.toString();
				var imported:Boolean = false;
				for each (importer in formatImporters)
				{
					if (importer.importOneFormat(propertyName,propertyValue))
					{
						imported = true;
						break;
					}
				}
				if (!imported)	// not a supported attribute
					handleUnknownAttribute (xmlToParse.name().localName, propertyName);}
		}
				
		static protected function extractAttributesHelper(curAttrs:Object, importer:TLFormatImporter):Object
		{
			if (curAttrs == null)
				return importer.result;
			
			if (importer.result == null)
				return curAttrs;
				
			var workAttrs:Object = new importer.classType(curAttrs);
			workAttrs.apply(importer.result);
			return workAttrs;
		}	
		
		/** Parse XML and convert to  TextFlow.
		 * @param xmlToParse	content to parse
		 * @param textFlow 		TextFlow we're parsing. If null, create or find a new TextFlow based on XML content
		 * @return TextFlow	the new TextFlow created as a result of the parse
		 */
		public function createTextFlowFromXML(xmlToParse:XML, newFlow:TextFlow = null):TextFlow
		{
			CONFIG::debug { assert(false,"missing override for createTextFlowFromXML"); }
			return null;
		}
		
		public function createParagraphFromXML(xmlToParse:XML):ParagraphElement
		{
			CONFIG::debug { assert(false,"missing override for createParagraphFromXML"); }
			return null;
		}
		
		public function createSpanFromXML(xmlToParse:XML):SpanElement
		{
			CONFIG::debug { assert(false,"missing override for createSpanFromXML"); }
			return null;
		}
		
		public function createBreakFromXML(xmlToParse:XML):BreakElement
		{
			parseAttributes(xmlToParse,null);	// no attributes allowed - reports errors
			return new BreakElement();
		}
		
		public function createTabFromXML(xmlToParse:XML):TabElement
		{
			parseAttributes(xmlToParse,null);	// reports errors
			return new TabElement();
		}
		
		/** Parse XML, convert to FlowElements and add to the parent.
		 * @param xmlToParse	content to parse
		 * @param parent 		the parent for the new content
		 */
		public function parseFlowChildren(xmlToParse:XML, parent:FlowGroupElement):void
		{
			parseFlowGroupElementChildren(xmlToParse, parent);
		}
		
		/** Parse XML, convert to FlowElements and add to the parent.
		 * @param xmlToParse	content to parse
		 * @param parent 		the parent for the new content
		 * @param chainedParent whether parent actually corresponds to xmlToParse or has been chained (such as when xmlToParse is a formatting element) 
		 */
		public function parseFlowGroupElementChildren(xmlToParse:XML, parent:FlowGroupElement, exceptionElements:Object = null, chainedParent:Boolean=false):void
		{
			for each (var child:XML in xmlToParse.children())
			{
				if (child.nodeKind() == "element")
				{
					parseObject(child.name().localName, child, parent, exceptionElements);
				}
				// look for mixed content here
 				else if (child.nodeKind() == "text") 
 				{
 					var txt:String = child.toString();
 					// Strip whitespace-only text appearing as a child of a container-formatted element
 					var strip:Boolean = false;
 					if (parent is ContainerFormattedElement)
 					{
						var whiteArray:Array = txt.match(anyPrintChar);
						strip = (whiteArray.length == 0);
					}
					
 					if (!strip) 
 					{
						// note, we don't want to set the paraFormat so that we inherit them from the TextFlow
						var span:SpanElement = new SpanElement();
						span.text = txt;
						addChild(parent, span);
					}
				}
			}
			
			// no implied paragraph should extend across container elements
			if (!chainedParent && parent is ContainerFormattedElement)
				resetImpliedPara();
		}
			
		public function createParagraphFlowFromXML(xmlToParse:XML, newFlow:TextFlow = null):TextFlow
		{
			CONFIG::debug { assert(false,"missing override for createParagraphFlowFromXML"); }	// client must override
			return null;
		}
		
		tlf_internal function parseObject(name:String, xmlToParse:XML, parent:FlowGroupElement, exceptionElements:Object=null):void
		{
			if (!checkNamespace(xmlToParse))
				return;

			var info:FlowElementInfo = _config.lookup(name);
			if (!info)
			{
				if (exceptionElements == null || exceptionElements[name] === undefined)
					handleUnknownElement (name, xmlToParse, parent);		
			}
			else
				info.parser(this, xmlToParse, parent);
		}
		
		protected function handleUnknownElement(name:String, xmlToParse:XML, parent:FlowGroupElement):void
		{
			reportError(GlobalSettings.getResourceStringFunction("unknownElement", [ name ]));	
		}
		
		protected function handleUnknownAttribute(elementName:String, propertyName:String):void
		{
			reportError(GlobalSettings.getResourceStringFunction("unknownAttribute", [ propertyName, elementName ]));	
		}
		
		protected function getElementInfo(xmlToParse:XML):FlowElementInfo
		{
			return _config.lookup(xmlToParse.name().localName);
		}
		
		protected function GetClass(xmlToParse:XML):Class
		{
			var info:FlowElementInfo = _config.lookup(xmlToParse.name().localName);
			return info ? info.flowClass : null;
		}
		
		// In the text model, non-FlowParagraphElements (i.e. spans, images, links, TCY) cannot be children of a ContainerElement (TextFlow, Div etc.)
		// They can only be children of paragraphs or subparagraph blocks. 
		// In XML, however, <p> elements can be implied (for example, a <span> may appear as a direct child of <flow>).  
		// So, while parsing the XML, if we enounter a non-FlowParagraphElement child of a ContainerElement 
		// 1. an explicitly created paragraph is used as the parent instead
		// 2. such explicitly created paragraphs are shared by adjacent flow elements provided there isn't an intervening FlowParagraphElement		
		private var _impliedPara:ParagraphElement = null; 
		
		/**
		 * @private
		 * Helper function for adding a child flow element that honors throwOnError setting and uses the parent override
		 * NOTE: You MUST NOT call addChild directly unless you are sure
		 * - There is not possibility of an implied paragraph, and
		 * - Parent is of type that can contain child
		*/
		tlf_internal function addChild(parent:FlowGroupElement, child:FlowElement):Boolean
		{
			if (child is ParagraphFormattedElement)
			{
				// Reset due to possibly intervening FlowParagrahElement; See note 2. above
				resetImpliedPara();
			}
			else if (parent is ContainerFormattedElement)
			{
				// See note 1. above
				if (!_impliedPara)
				{
					// Derived classes may have special behavior for <p> tags. Implied paragraphs may need the same behavior.
					// So call createParagraphFromXML, don't just instantiate a ParagraphElement 
					_impliedPara = createParagraphFromXML(<p/>); 
					parent.addChild(_impliedPara);
				}
				
				parent = _impliedPara;
			}	
			
			if (_throwOnError)
				parent.addChild(child);
			else
			{
				try
				{
					parent.addChild(child);
				}
				catch (e:*)
				{
					reportError(e); 	
					return false;
				}
			}
			
			return true;
		} 
		
		tlf_internal function resetImpliedPara():void
		{
			if (_impliedPara)
			{
				onResetImpliedPara(_impliedPara);
				_impliedPara = null;
			}
		}
		
		protected function onResetImpliedPara(para:ParagraphElement):void
		{
		}

		/** Errors encountered while parsing. 
		 * Value is a vector of Strings.
		 */
		public function get errors():Vector.<String>
		{
			return _errors;
		}
		
		/** Errors will cause exceptions if throwOnError is true. */
		public function get throwOnError():Boolean
		{
			return _throwOnError;
		}
		public function set throwOnError(value:Boolean):void
		{
			_throwOnError = value;
		}
		
		/** Register an error that was encountered while parsing. If throwOnError
		 * is true, the error causes an exception. Otherwise it is logged and parsing
		 * continues.
		 * @param error	the String that describes the error
		 */
		protected function reportError(error:String):void
		{
			if (_throwOnError)
				throw new Error(error);
			
			if (!_errors)
				_errors = new Vector.<String>();
			_errors.push(error);
		}
	}
}
