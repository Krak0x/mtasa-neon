// Export one function from a Ghidra headless analysis.
// @category MTA.Neon

import java.io.FileWriter;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class ExportDecompiledFunction extends GhidraScript
{
    @Override
    protected void run() throws Exception
    {
        String[] arguments = getScriptArgs();
        if (arguments.length != 2)
            throw new IllegalArgumentException("Expected: <address> <output-file>");

        Address address = currentProgram.getAddressFactory().getAddress(arguments[0]);
        Function function = getFunctionContaining(address);
        if (function == null)
            throw new IllegalStateException("No function contains " + address);

        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        DecompileResults results = decompiler.decompileFunction(function, 120, monitor);
        if (!results.decompileCompleted())
            throw new IllegalStateException(results.getErrorMessage());

        try (FileWriter output = new FileWriter(arguments[1]))
        {
            output.write(results.getDecompiledFunction().getC());
        }
    }
}
