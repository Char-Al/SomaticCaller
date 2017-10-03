import org.broadinstitute.gatk.queue.QScript
import org.broadinstitute.gatk.queue.extensions.gatk._
import org.broadinstitute.gatk.tools.walkers.genotyper.OutputMode

class perform_Mutect2_Calling extends QScript {

 // Script Arguments passed from command line

	@Input(doc="Tumor or affected sample", shortName="tumor", required=true)
	var tumorIn: File = _
	@Input(doc="Normal sample", shortName="normal", required=true)
	var normalIn: File = _
	@Input(doc="dbsnp", shortName="dbsnp", required=true)
	var dbsnpFile: File = _
	@Input(doc="cosmic", shortName="cosmic", required=true)
	var cosmicFile: File = _
	@Input(doc="Normal panel", shortName="normal_panel", required=true)
	var normal_panelFile: File = _
	@Argument(shortName = "o",  required=true, doc = "Output file")
	var outputFile: File = _
	@Input(doc="Reference file for the bam files", shortName="R")
	var referenceFile: File = _

	// Add functions hard-coded in the script
	def script() {
		val Mutect2_Calling = new MuTect2
		Mutect2_Calling.scatterCount = 24
		Mutect2_Calling.input_file = List(new TaggedFile(tumorIn, "tumor"), new TaggedFile(normalIn, "normal"))
		Mutect2_Calling.dbsnp = dbsnpFile
		Mutect2_Calling.cosmic = Seq(cosmicFile)
		Mutect2_Calling.normal_panel = Seq(normal_panelFile)
		Mutect2_Calling.output_mode = OutputMode.EMIT_VARIANTS_ONLY
		Mutect2_Calling.out = outputFile
		Mutect2_Calling.R = referenceFile

		add(Mutect2_Calling)
	}
}


