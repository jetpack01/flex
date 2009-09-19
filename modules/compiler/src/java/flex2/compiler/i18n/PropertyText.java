////////////////////////////////////////////////////////////////////////////////
//
//  ADOBE SYSTEMS INCORPORATED
//  Copyright 2007 Adobe Systems Incorporated
//  All Rights Reserved.
//
//  NOTICE: Adobe permits you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
////////////////////////////////////////////////////////////////////////////////

package flex2.compiler.i18n;

import java.io.IOException;
import java.io.Reader;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;

import flex2.compiler.Source;
import flex2.compiler.SymbolTable;
import flex2.compiler.common.CompilerConfiguration;
import flex2.compiler.common.MxmlConfiguration;
import flex2.compiler.io.ResourceFile;
import flex2.compiler.mxml.lang.StandardDefs;
import flex2.compiler.mxml.rep.AtEmbed;
import flex2.compiler.util.OrderedProperties;
import flex2.compiler.util.ThreadLocalToolkit;
import flex2.compiler.util.CompilerMessage.CompilerError;

/**
 * 
 * @author Gordon Smith
 * @author Clement Wong
 */
public class PropertyText extends OrderedProperties
{
    private static final long serialVersionUID = -4748416824610507873L;
    // things that can start a value
    public static final String CLASS_REFERENCE = "ClassReference(";
    public static final String EMBED = "Embed(";

	public PropertyText(CompilerConfiguration configuration, SymbolTable symbolTable,
	        Source source, String locale, StandardDefs standardDefs)
	{
		super();
		this.symbolTable = symbolTable;
		this.source = source;
		this.locale = locale;
		imports = new HashSet<String>();
		atEmbeds = new HashMap<String, AtEmbed>();

		imports.add(standardDefs.CLASS_RESOURCEBUNDLE_DOT);

		int version = configuration.getCompatibilityVersion();
		flex2Compatible = version < MxmlConfiguration.VERSION_3_0;
    }

	private boolean flex2Compatible;
	private SymbolTable symbolTable;
	private Source source;
	private String locale;

    /**
     * If a ClassReference("foo.bar") directive is encountered
     * as a resource value in a .properties file,
     * then "foo.bar" is added to this Set via addImport().
     * When the ResourceBundle subclass is autogenerated,
     * this set of classes to be imported is used
	 * to autogenerate import statements like
     *   import "foo.bar";
     */
    Set<String> imports;

    /**
     * If an Embed(...) directive is encountered
     * as a resource value in a .properties file,
     * then an AtEmbed object is added to this Map
     * via addAtEmbed().
     * When the ResourceBundle subclass is autogenerated,
     * this Map is used to autogenerated embedded class
  	 * declarations like
     *   [Embed(...)]
     *   private static var foo_class:Class;
     */
    Map<String, AtEmbed> atEmbeds;

    public void load(Reader reader) throws IOException
    {
    	super.load(reader);
    	
    	for (Iterator i = keySet().iterator(); i.hasNext(); )
    	{
    		String key = (String) i.next(), value = getProperty(key);
    		Object valueObject;
    		
            if (value.startsWith(CLASS_REFERENCE))
            {
                valueObject = processClassReference(key, value);
            }
            else if (value.startsWith(EMBED))
            {
                valueObject = processEmbed(key, value);
            }
            else
            {
            	valueObject = value;
            }
            
            if (valueObject != null)
            {
            	put(key, valueObject);
            }
    	}
    }
    
    /*
     * In Java .properties files, an equal sign, a colon,
     * a space, or a tab can be used to separate the key and value.
     * The getTerminators() method of OrderedProperties
     * returns all of these in order to act like Java.
     * However, Flex 2 supported only '=', while Flex 3 works like Java.
     * This override implements that compatibility logic.
     */
    protected String getTerminators()
    {
    	return flex2Compatible ? "=" : super.getTerminators();
    }
    
    /*
     * In Java .properties files, no "bad" characters 
     * are removed from the key or value.
     * The removeBadChars() method of OrderedProperties
     * does nothing in order to act like Java.
     * However, Flex 2 removed double-quotes, carriage returns, and newlines.
     * This was a bad idea, and Flex 3 works like Java.
     * This override implements that compatibility logic.
     */
    protected String removeBadChars(String propLine, String string, boolean isValue)
    {
		if (flex2Compatible)
		{
			string = removeBadChars(propLine, string, "\\n");
			string = removeBadChars(propLine, string, "\\r");
			if (isValue && !string.startsWith(CLASS_REFERENCE) && !string.startsWith(EMBED))
			{
				string = removeBadChars(propLine, string, "\"");
			}
		}
		return string;
    }

	// We remove any \n, \r, " characters.  We don't, however, remove \\n, \\r, \\"
    // This happens only in Flex 2; Flex 3 parses .properties files like Java,
    // except for using UTF-8 encoding.
	private static String removeBadChars(String propLine, String str, String bad)
	{
	    int index = str.indexOf(bad);
		boolean ignore = index != 0 && str.regionMatches(index - 1, "\\", 0, 1);

	    if(index == -1)
	        return str;

	    StringBuilder buf = new StringBuilder(str.length());
	    int lastIndex = 0;
		boolean errorMessage = false;
	    while(index != -1) {
	        buf.append(str.substring(lastIndex, index));
		    if (ignore)
		    {
			    buf.append(bad);
		    }
		    else if (! errorMessage)
		    {
			    errorMessage = true;
			    ThreadLocalToolkit.log(new RemovedFromProperty(bad, propLine));
		    }
	        lastIndex = index + bad.length();
	        index = str.indexOf(bad, lastIndex);
		    ignore = index != 0 && str.regionMatches(index - 1, "\\", 0, 1);
	    }

	    // add in last chunk
	    buf.append(str.substring(lastIndex));

	    return buf.toString();
	}

    /**
     * Called when we find a resource value which is a ClassReference() directive.
     * Returns a ClassReference object which holds the class parameter.
     * Also adds the class to the i18n compiler's list of imports
     * to be put into the autogenerated resource bundle.
     * 
     * The ClassReference() directive is also supported in <mx:Script> blocks and CSS files;
     * this method is similar to processClassReference() in StyleDef.
     */
    private ClassReference processClassReference(String key, String value)
    {
        ClassReference classReference = null;
        int lineNumber = (lines.get(key)).intValue();
        
        String parameter = value.substring(CLASS_REFERENCE.length(), value.length() - 1).trim();
        if ((parameter.charAt(0) == '"') && (parameter.indexOf('"', 1) == parameter.length() - 1))
        {
            parameter = parameter.substring(1, parameter.length() - 1);
            classReference = new ClassReference(parameter, lineNumber);
            imports.add(parameter);
        }
		else if (parameter.equals("null"))
		{
			classReference = new ClassReference(null, lineNumber);
		}
        else
        {
            InvalidClassReference invalidClassReference = new InvalidClassReference();
            invalidClassReference.path = getPropertyFileName();
            invalidClassReference.line = lineNumber;
            ThreadLocalToolkit.log(invalidClassReference);
        }

        return classReference;
    }

    /**
     * Called when we find a resource value which is an Embed() directive.
     * Returns an Embed object which keeps track of the parsed parameters.
     * Also adds it to the compiler...
     * 
     * The Embed() directive is also supported in <mx:Script> blocks and CSS files;
     */
	private AtEmbed processEmbed(String key, String value)
	{
        int lineNumber = (lines.get(key)).intValue();
        String propertiesPath = getPropertyFileName();
        AtEmbed atEmbed = AtEmbed.create(symbolTable.perCompileData, source, value,
                                         propertiesPath, lineNumber, "_embed_properties_");

        if (atEmbed != null)
        {
            atEmbeds.put(atEmbed.getPropName(), atEmbed);
        }

        return atEmbed;
    }

	private String getPropertyFileName()
	{
		ResourceFile f = (ResourceFile) source.getBackingFile();
		f.setLocale(locale);
		return f.getNameForReporting();
	}
	
    public static class InvalidClassReference extends CompilerError
    {
        private static final long serialVersionUID = -1168616929938888558L;

        public InvalidClassReference()
        {
        }
    }
}
