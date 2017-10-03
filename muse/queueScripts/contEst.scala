import org.broadinstitute.gatk.queue.QScript
import org.broadinstitute.gatk.queue.extensions.gatk._
import org.broadinstitute.gatk.utils.interval.IntervalSetRule

class perform_ContEst_PoN extends QScript {

 // Script Arguments passed from command line

	@Input(doc="eval sample", shortName="eval", required=false)
	var evalIn: File = _
	@Input(doc="Genotypes", shortName="genotypes", required=false)
	var genotypesIn: File = _
	@Input(doc="Hapmap", shortName="popfile", required=true)
	var hapmapFile: File = _
	@Argument(shortName = "o",  required=true, doc = "Output file")
	var outputFile: File = _
	@Input(doc="Reference file for the bam files", shortName="R")
	var referenceFile: File = _
	
	// Add functions hard-coded in the script
	def script() {
		val contest = new ContEst
		contest.scatterCount = 24
		contest.input_file = List(new TaggedFile(evalIn, "eval"))
		contest.genotypes = genotypesIn
		contest.popfile = hapmapFile
		contest.interval_set_rule = IntervalSetRule.INTERSECTION
		contest.out = outputFile
		contest.R = referenceFile

		add(contest)
	}
}
