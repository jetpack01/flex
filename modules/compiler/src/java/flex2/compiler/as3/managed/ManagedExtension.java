////////////////////////////////////////////////////////////////////////////////
//
//  ADOBE SYSTEMS INCORPORATED
//  Copyright 2005-2006 Adobe Systems Incorporated
//  All Rights Reserved.
//
//  NOTICE: Adobe permits you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
////////////////////////////////////////////////////////////////////////////////

package flex2.compiler.as3.managed;

import flex.messaging.config.ServicesDependencies;
import flex2.compiler.CompilationUnit;
import flex2.compiler.as3.binding.TypeAnalyzer;
import flex2.compiler.as3.genext.GenerativeExtension;
import flex2.compiler.as3.genext.GenerativeFirstPassEvaluator;
import flex2.compiler.as3.reflect.TypeTable;
import flex2.compiler.mxml.lang.StandardDefs;
import flex2.compiler.util.MultiName;
import macromedia.asc.parser.Evaluator;

/**
 * @author Paul Reilly
 */
public final class ManagedExtension extends GenerativeExtension
{
    public static final String IMANAGED = "IManaged";

	private ServicesDependencies servicesDependencies;
    
	public ManagedExtension(String generatedOutputDirectory, boolean generateAbstractSyntaxTree, boolean processComments)
	{
		this(generatedOutputDirectory, generateAbstractSyntaxTree, null, processComments);
	}

    public ManagedExtension(String generatedOutputDirectory, boolean generateAbstractSyntaxTree,
                            ServicesDependencies services, boolean processComments)
    {
        super(generatedOutputDirectory, generateAbstractSyntaxTree, processComments );
        servicesDependencies = services;
    }

	/**
	 * Add the MultiNames for the definitions that the BindableSecondPassEvaluator
	 * requires.
	 */
    protected void addInheritance(CompilationUnit unit)
    {
        unit.inheritance.add(new MultiName(StandardDefs.PACKAGE_FLASH_EVENTS, IEVENT_DISPATCHER));
        unit.inheritance.add(new MultiName(unit.getStandardDefs().getDataPackage(), IMANAGED));
    }

	/**
	 *
	 */
	protected GenerativeFirstPassEvaluator getFirstPassEvaluator(CompilationUnit unit,
                                                                 TypeTable typeTable)
	{
		return new ManagedFirstPassEvaluator(typeTable, unit.getStandardDefs(), unit.metadata, servicesDependencies);
	}

	/**
	 *
	 */
	protected String getFirstPassEvaluatorKey()
    {
        return "ManagedFirstPassEvaluator";
    }

	/**
	 *
	 */
	protected Evaluator getSecondPassEvaluator(CompilationUnit unit,
                                               TypeAnalyzer typeAnalyzer,
                                               GenerativeFirstPassEvaluator firstPassEvaluator)
	{
		return new ManagedSecondPassEvaluator(unit, firstPassEvaluator.getClassMap(),
                                              typeAnalyzer, generatedOutputDirectory,
                                              generateAbstractSyntaxTree, processComments);
	}

}
