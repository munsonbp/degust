require('./lib/numeric-1.2.6.js')

class ScatterPlot
    constructor: (elem, tot_width=800, tot_height=400) ->
        margin = {top: 20, right: 380, bottom: 40, left: 40}
        @width = tot_width - margin.left - margin.right
        @height = tot_height - margin.top - margin.bottom

        @x = d3.scale.linear()
               .range([0, @width])

        @y = d3.scale.linear()
               .range([@height, 0])

        @color = d3.scale.category10()

        @xAxis = d3.svg.axis()
                   .scale(@x)
                   .orient("bottom")

        @yAxis = d3.svg.axis()
                   .scale(@y)
                   .orient("left");

        @svg = d3.select(elem).append("svg")
                 .attr("width", @width + margin.left + margin.right)
                 .attr("height", @height + margin.top + margin.bottom)
                .append("g")
                 .attr("transform", "translate(" + margin.left + "," + margin.top + ")")

    # draw(data,labels)
    #   data - array of rows.  First row is all x-coordinates (dimension 1)
    #                          Second row is all y-coordinates (dimension 2)
    #   labels - array of samples.  sample.name, and (sample.parent for colouring)
    draw: (data, labels, dims) ->
        [dim1,dim2] = dims
        @x.domain(d3.extent(data[dim1]))
        @y.domain(d3.extent(data[dim2]))

        # Easier to plot with array of
        locs = d3.transpose(data)

        @svg.selectAll(".axis").remove()
        @svg.append("g")
            .attr("class", "x axis")
            .attr("transform", "translate(0," + @height + ")")
            .call(@xAxis)
          .append("text")
            .attr("class", "label")
            .attr("x", @width)
            .attr("y", 10)
            .style("text-anchor", "start")
            .text("PCA dim #{dim1}");

        @svg.append("g")
            .attr("class", "y axis")
            .call(@yAxis)
          .append("text")
            .attr("class", "label")
            .attr("transform", "rotate(-90)")
            .attr("y", 6)
            .attr("dy", ".71em")
            .style("text-anchor", "end")
            .text("PCA dim #{dim2}");

        dots = @svg.selectAll(".dot")
                   .data(locs)
        dots.exit().remove()

        # Create the dots and labels
        dot_g = dots.enter().append("g")
                    .attr("class", "dot")
        dot_g.append("circle")
             .attr("r", 3.5)
             .attr("cx",0)
             .attr("cy",0)
             .style("fill", (d,i) => @color(labels[i].parent))
        dot_g.append("text")
             .attr('class',"labels")
             .text((d,i) -> labels[i].name)
             .attr('x',3)
             .attr('y',-3)
             .style("fill", (d,i) => @color(labels[i].parent))

        # Position the dots
        dots.transition()
            .attr("transform", (d) => "translate(#{@x(d[dim1])},#{@y(d[dim2])})")

class PCA
    @pca: (matrix) ->
        # Subtract column-wise mean (need zero-mean for PCA).
        #m = X.length
        #X = numeric.sub(X, numeric.sum(X)/(m*m))

        X = matrix.map((r) -> mean = 1.0*numeric.sum(r)/r.length; numeric.sub(r,mean))
        X = numeric.transpose(X)
        #console.log(matrix,X)


        #sigma = numeric.div(numeric.dot(numeric.transpose(X), X), X.length)
        #sigma = numeric.dot(numeric.transpose(X), X)
        sigma = numeric.dot(X,numeric.transpose(X))
        svd = numeric.svd(sigma)
        #console.log("svd",svd);
        #return svd.U
        # scale the coordinates back so can interpret at RMS expression
        # (from http://www.ats.ucla.edu/stat/r/pages/svd_demos.htm)
        numeric.dot(svd.V, numeric.sqrt(numeric.diag(svd.S)))

    @variance: (X) ->
        sz = X.length
        numeric.sum(numeric.pow(X,2))/sz - Math.pow(numeric.sum(X),2)/(sz*sz)

    @to_dist: (a,b) ->
        diffs = numeric.sub(a,b)
        return Math.sqrt(numeric.sum(numeric.pow(diffs,2))/a.length)

# Implement Paul Harrison's glog moderation
log_moderation = 10.0
glog = (x,m) ->
    Math.log( (x + Math.sqrt(x*x + 4*m*m))/2 ) / Math.log(2)

variance_key = "_variance"
transform_key = "_transformed_"

class GenePCA
    constructor: (@opts) ->
        @scatter = new ScatterPlot(@opts.elem)

    # Note, this is naughty - it writes to the 'data' array a "_variance" column
    # and several "_transformed_" columns
    update_data: (@data, @columns) ->
        # 'data' - one row per gene.
        max = @data.length
        #@top_n.set_max(max)

        # Counts is an array for each gene.  Each of those is an array of counts
        #raw_counts = @data.map((row) => @columns.map((c) -> row[c.idx]) )

        #lib_size = d3.transpose(raw_counts).map((l) -> d3.sum(l))
        #avg_lib_size = d3.mean(lib_size)

        @redraw()

    _compute_variance: (row) ->
        transformed =  @columns.map((col) ->
            val = row[col.idx]
            #t_val = glog(1000000.0 * val/size, 1000000.0 * log_moderation / avg_lib_size)
            t_val = Math.log(log_moderation + val)/Math.log(2)
            row[transform_key+col.idx] = t_val
            t_val
        )
        row[variance_key] = PCA.variance(transformed)

    redraw: () ->
        [skip_genes, num_genes, dims] = @opts.num_filter()
        dims = dims.split(',').map((v) -> +v)[0..1]
        dims = [1,2] if dims.length!=2

        # Log transform counts
        kept_data = @data.filter((d) => @opts.filter(d))
                       #  .map((row) -> d3.zip(row, lib_size).map(([val,size]) ->
        kept_data.forEach((row) => @_compute_variance(row))

        top_genes = kept_data.sort((a,b) -> b[variance_key] - a[variance_key])
        top_genes = top_genes[skip_genes ... (skip_genes + num_genes)]

        @opts.gene_table.set_data(top_genes) if @opts.gene_table

        # Transpose to row per sample.
        transformed = top_genes.map((row) => @columns.map((col) ->
                                                row[transform_key+col.idx]))
        by_gene = numeric.transpose(transformed)

        # Compute pair-wise distances
        dist = []
        for i in [0...by_gene.length]
            dist[i] ?= []
            for j in [i...by_gene.length]
                dist[j] ?= []
                if i==j
                    dist[i][j] = 0
                else
                    dist[i][j] = dist[j][i] = PCA.to_dist(by_gene[i], by_gene[j])

        comp = PCA.pca(dist)
        #console.log("dist",dist,"comp",comp);
        @scatter.draw(numeric.transpose(comp), @columns, dims)

    brush: () ->
        @redraw()

    highlight: () ->
        # Pass
    unhighlight: () ->
        # Pass

window.GenePCA = GenePCA


# mat<-matrix(c(10,4,34,46,1204,4798,510,  771,439,3,3,827,1660,549,  56,44,47,51,966,2146,470),nrow=3,byrow=T)