import org.broadinstitute.gatk.queue.QScript
import org.broadinstitute.gatk.queue.extensions.gatk._

class perform_Mutect2_PoN extends QScript {

 // Script Arguments passed from command line

	@Input(doc="Tumor or affected sample", shortName="tumor", required=true)
	var tumorIn: File = _
	@Input(doc="dbsnp", shortName="dbsnp", required=true)
	var dbsnpFile: File = _
	@Argument(shortName = "o",  required=true, doc = "Output file")
	var outputFile: File = _
	@Input(doc="Reference file for the bam files", shortName="R")
	var referenceFile: File = _

	// Add functions hard-coded in the script
	def script() {
		val Mutect2_PoN = new MuTect2
		Mutect2_PoN.scatterCount = 24
		Mutect2_PoN.input_file = List(new TaggedFile(tumorIn, "tumor"))
		Mutect2_PoN.dbsnp = dbsnpFile
		Mutect2_PoN.artifact_detection_mode
		Mutect2_PoN.out = outputFile
		Mutect2_PoN.R = referenceFile

		add(Mutect2_PoN)
	}
}
