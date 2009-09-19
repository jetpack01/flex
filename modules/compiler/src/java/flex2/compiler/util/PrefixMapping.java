////////////////////////////////////////////////////////////////////////////////
//
//  ADOBE SYSTEMS INCORPORATED
//  Copyright 2004-2007 Adobe Systems Incorporated
//  All Rights Reserved.
//
//  NOTICE: Adobe permits you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
////////////////////////////////////////////////////////////////////////////////

package flex2.compiler.util;

import java.util.Stack;

import flex2.compiler.mxml.dom.Node;
import flex2.compiler.mxml.rep.BindingExpression;

/**
 * This class represents a namespace prefix for a XML or XMLList bindable expression.
 *
 */

public class PrefixMapping
{    
    int ns;
    String uri;
    
    // want unique names across objects since the namespace declarations may
    // end up in the same scope
    private static int namespaceNum = 0;
    
    public PrefixMapping(String uri)
    {
        this.ns = ++namespaceNum;
        this.uri = uri;
    }

    public boolean equals(Object obj)
    {
        return uri.equals(obj);
    }
    
    public int hashCode()
    {
        return uri.hashCode();
    }

    public String getUri()
    {
        return uri;
    }

    public int getNs()
    {
        return ns;
    }
    
    /**
     * Push the PrefixMapping for the node onto the namespaces stack.
     * @param node
     * @param namespaces
     */
    public static void pushNodeNamespace(Node node, Stack<PrefixMapping> namespaces)
    {
        String uri = node.getNamespace();
        
        for (int i = 0, size = namespaces.size(); i < size; i++)
        {
            PrefixMapping pm = namespaces.get(i);
            if (pm.equals(uri))
            {
                namespaces.push(pm);
                return;
            }
        }

        namespaces.push(new PrefixMapping(uri));        
    }

    /**
     * Used for XML attributes.  If the mapping doesn't already exist, a new
     * unique number is returned.  The mapping is added directly to the binding
     * expression without first generating a PrefixMapping.  This problem with
     * this is the same uri can generated multiple namespace declarations.  There
     * is room for improvement here.
     * @param nsUri
     * @param namespaces
     * @return
     */
    public static int getNamespaceId(String nsUri, Stack<PrefixMapping> namespaces)
    {
        for (int i = 0, size = namespaces.size(); i < size; i++)
        {
            PrefixMapping pm = namespaces.get(i);
            if (pm.equals(nsUri))
            {
                return pm.getNs();
            }
        }       
        
        return ++namespaceNum;
    }
    
    public static void popNodeNamespace(Stack<PrefixMapping> namespaces)
    {
        namespaces.pop();
    }

    /**
     * Add all the namespaces to the binding expression.
     * @param be
     * @param namespaces
     */
    public static void pushNamespaces(BindingExpression be, Stack<PrefixMapping> namespaces)
    {
        for (int i = 0, count = namespaces.size(); i < count; i++)
        {
            PrefixMapping pm = namespaces.get(i);
            be.addNamespace(pm.getUri(), pm.getNs());
        }
    }    
}

